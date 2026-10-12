import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/patch_file.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Runs real git as a user with a German locale would, so git's messages
/// come back translated unless a caller pins them.
class _GermanGit implements GitService {
  const _GermanGit();
  static const _svc = SystemGitService();

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _svc.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {'LC_ALL': 'de_DE.UTF-8', 'LANGUAGE': 'de', ...?environment},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => _svc.version();
  @override
  Future<bool> isRepository(String path) => _svc.isRepository(path);
}

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<String> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
    return r.out;
  }

  File f(String name) => File('${dir.path}/$name');
  Future<String> read(String name) => f(name).readAsString();
  Future<String> status() => g(['status', '--porcelain']);

  late ProviderContainer c;
  RepoActions actions() => c.read(repoActionsProvider(dir.path));
  late List<int> series;
  late List<int> diff;

  setUp(() async {
    c = ProviderContainer();
    dir = await Directory.systemTemp.createTemp('mergelio_apply_patch_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await f('f').writeAsString('a\nb\nc\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    // A two-commit series on a side branch, exported both ways.
    await g(['switch', '-q', '-c', 'side']);
    await f('f').writeAsString('a\nB\nc\n');
    await g(['commit', '-q', '-am', 'one']);
    await f('f').writeAsString('a\nB\nc\nd\n');
    await f('g').writeAsString('new\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'two']);
    series = utf8.encode(
      (await svc.run([
        'format-patch',
        '--stdout',
        'main..side',
      ], repoPath: dir.path)).stdout,
    );
    diff = utf8.encode(
      (await svc.run(['diff', 'main', 'side'], repoPath: dir.path)).stdout,
    );
    await g(['switch', '-q', 'main']);
  });

  tearDown(() async {
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('previews a mailbox series: files, subjects, modes', () async {
    final p = await actions().previewPatch(series);
    expect(p.subjects, ['one', 'two']);
    expect(p.files.map((s) => (s.path, s.added, s.deleted)), [
      ('f', 2, 1),
      ('g', 1, 0),
    ]);
    expect(p.modes, [PatchMode.worktree, PatchMode.stage]);
  });

  test('a file that is no patch throws, and toasts nothing', () async {
    await expectLater(
      actions().previewPatch(utf8.encode('hello\n')),
      throwsA(isA<GitException>()),
    );
    // The caller words it in the user's language.
    expect(c.read(toastProvider), isEmpty);
  });

  test('a diff that no longer fits offers only a 3-way merge', () async {
    await f('f').writeAsString('a\nX\nc\n');
    await g(['commit', '-q', '-am', 'diverge']);
    final p = await actions().previewPatch(diff);
    expect(p.modes, [PatchMode.threeWay]);
    expect(p.threeWay, ThreeWayCheck.conflicts);
    expect(p.error, contains('does not apply'));
  });

  test('an index that differs from the file rules out staging', () async {
    await f('f').writeAsString('staged\n');
    await g(['add', 'f']);
    await f('f').writeAsString('a\nb\nc\n');
    final p = await actions().previewPatch(diff);
    expect(p.modes, [PatchMode.worktree]);
  });

  test('applies to the working tree only; undo and redo', () async {
    final head = await g(['rev-parse', 'HEAD']);
    final a = actions();
    expect(
      await a.applyPatchFile(series, PatchMode.worktree),
      PatchOutcome.applied,
    );
    expect(await read('f'), 'a\nB\nc\nd\n');
    expect(await status(), ' M f\n?? g'.trim());
    // Applying never commits, even a mailbox.
    expect(await g(['rev-parse', 'HEAD']), head);

    await a.undo();
    expect(await read('f'), 'a\nb\nc\n');
    expect(f('g').existsSync(), isFalse);
    expect(await status(), '');

    await a.redo();
    expect(await read('f'), 'a\nB\nc\nd\n');
  });

  test('applies and stages; undo unstages and reverts', () async {
    final a = actions();
    expect(
      await a.applyPatchFile(series, PatchMode.stage),
      PatchOutcome.applied,
    );
    expect(await status(), 'M  f\nA  g');

    await a.undo();
    expect(await status(), '');
    expect(await read('f'), 'a\nb\nc\n');
  });

  test('a 3-way merge leaves conflicts and records no undo', () async {
    await f('f').writeAsString('a\nX\nc\n');
    await g(['commit', '-q', '-am', 'diverge']);
    final a = actions();
    expect(
      await a.applyPatchFile(diff, PatchMode.threeWay),
      PatchOutcome.conflicts,
    );
    expect(await g(['ls-files', '-u']), isNotEmpty);
    expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    expect(c.read(toastProvider), isEmpty);
  });

  test('a 3-way merge of changes that do not touch applies cleanly', () async {
    // The patch changes line 5; the branch moved line 2, inside the patch's
    // context, so a direct apply fails but the merge has nothing to resolve.
    final lines = [for (var i = 1; i <= 10; i++) 'l$i'];
    await f('h').writeAsString('${lines.join('\n')}\n');
    await g(['add', 'h']);
    await g(['commit', '-q', '-m', 'h']);
    String text(int at, String line) =>
        '${(List.of(lines)..[at] = line).join('\n')}\n';
    await f('h').writeAsString(text(4, 'L5'));
    final patch = utf8.encode(
      (await svc.run(['diff'], repoPath: dir.path)).stdout,
    );
    await g(['checkout', '--', 'h']);
    await f('h').writeAsString(text(1, 'L2'));
    await g(['commit', '-q', '-am', 'move l2']);
    final a = actions();
    final p = await a.previewPatch(patch);
    expect(p.modes, [PatchMode.threeWay]);
    expect(p.threeWay, ThreeWayCheck.clean);
    expect(
      await a.applyPatchFile(patch, PatchMode.threeWay),
      PatchOutcome.applied,
    );
    expect(await read('h'), contains('L2\nl3\nl4\nL5\n'));
    expect(await g(['ls-files', '-u']), isEmpty);
  });

  test('a failed apply reports failed with an error toast', () async {
    await f('f').writeAsString('a\nX\nc\n');
    expect(
      await actions().applyPatchFile(diff, PatchMode.worktree),
      PatchOutcome.failed,
    );
    expect(await read('f'), 'a\nX\nc\n');
    expect(c.read(toastProvider).single.kind, ToastKind.error);
  });

  group('under a translated git', () {
    setUp(() {
      c.dispose();
      c = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(const _GermanGit())],
      );
    });

    test('still sees that a 3-way merge would conflict', () async {
      await f('f').writeAsString('a\nX\nc\n');
      await g(['commit', '-q', '-am', 'diverge']);
      final p = await actions().previewPatch(diff);
      expect(p.threeWay, ThreeWayCheck.conflicts);
    });

    test('still reports a conflicted 3-way merge as applied', () async {
      await f('f').writeAsString('a\nX\nc\n');
      await g(['commit', '-q', '-am', 'diverge']);
      expect(
        await actions().applyPatchFile(diff, PatchMode.threeWay),
        PatchOutcome.conflicts,
      );
    });
  });
}
