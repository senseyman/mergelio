import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

import 'support/hermetic_git.dart';

/// Fails every git call the way a git that cannot be started does.
class _NoGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => throw GitUnavailableException('git not found');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late Directory dir;
  late String v1;
  const svc = HermeticGit();

  Future<String> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
    return r.out;
  }

  File file(String name) => File('${dir.path}/$name');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_restore_rev_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await file('a.txt').writeAsString('v1\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'v1']);
    v1 = await g(['rev-parse', 'HEAD']);
    await file('a.txt').writeAsString('v2\n');
    await g(['commit', '-q', '-am', 'v2']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container({GitService git = svc}) {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('writes the old content, keeps the index, and undoes', () async {
    await file('a.txt').writeAsString('staged\n');
    await g(['add', 'a.txt']);
    await file('a.txt').writeAsString('working\n');
    final c = container();

    await c.read(repoActionsProvider(dir.path)).restoreFileVersion(v1, 'a.txt');

    expect(await file('a.txt').readAsString(), 'v1\n');
    expect(await g(['show', ':a.txt']), 'staged');

    await c.read(repoActionsProvider(dir.path)).undo();
    expect(await file('a.txt').readAsString(), 'working\n');
    expect(await g(['show', ':a.txt']), 'staged');

    await c.read(repoActionsProvider(dir.path)).redo();
    expect(await file('a.txt').readAsString(), 'v1\n');
  });

  test('says so when the working copy already matches the version', () async {
    final c = container();
    final head = await g(['rev-parse', 'HEAD']);

    await c
        .read(repoActionsProvider(dir.path))
        .restoreFileVersion(head, 'a.txt');

    expect(c.read(toastProvider).last.kind, ToastKind.info);
    expect(c.read(toastProvider).last.title, contains('already matches'));
    expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    expect(await file('a.txt').readAsString(), 'v2\n');
  });

  test('a restore that changed the file says it is done', () async {
    final c = container();

    await c.read(repoActionsProvider(dir.path)).restoreFileVersion(v1, 'a.txt');

    expect(c.read(toastProvider).last.kind, ToastKind.success);
    expect(c.read(undoProvider(dir.path)).canUndo, isTrue);
  });

  test('undo removes a file the restore brought back', () async {
    await g(['rm', '-q', 'a.txt']);
    await g(['commit', '-q', '-m', 'gone']);
    final c = container();

    await c.read(repoActionsProvider(dir.path)).restoreFileVersion(v1, 'a.txt');
    expect(await file('a.txt').readAsString(), 'v1\n');

    await c.read(repoActionsProvider(dir.path)).undo();
    expect(await file('a.txt').exists(), isFalse);
  });

  test('undo never writes through a symlink the restore brought', () async {
    final elsewhere = await Directory.systemTemp.createTemp('mergelio_out_');
    addTearDown(() => elsewhere.delete(recursive: true));
    final outside = File('${elsewhere.path}/outside.txt');
    await outside.writeAsString('outside\n');
    await file('a.txt').delete();
    await Link('${dir.path}/a.txt').create(outside.path);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'link']);
    final linked = await g(['rev-parse', 'HEAD']);
    await Link('${dir.path}/a.txt').delete();
    await file('a.txt').writeAsString('regular\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'regular']);
    await file('a.txt').writeAsString('working\n');
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));

    await actions.restoreFileVersion(linked, 'a.txt');
    expect(FileSystemEntity.isLinkSync('${dir.path}/a.txt'), isTrue);

    await actions.undo();
    expect(FileSystemEntity.isLinkSync('${dir.path}/a.txt'), isFalse);
    expect(await file('a.txt').readAsString(), 'working\n');
    expect(await outside.readAsString(), 'outside\n');

    // And back the other way: undo of a restore over the link recreates it.
    await g(['checkout', '-q', '--', 'a.txt']);
    await g(['checkout', '-q', linked, '--', 'a.txt']);
    await actions.restoreFileVersion(v1, 'a.txt');
    expect(FileSystemEntity.isLinkSync('${dir.path}/a.txt'), isFalse);
    await actions.undo();
    expect(await Link('${dir.path}/a.txt').target(), outside.path);
    expect(await outside.readAsString(), 'outside\n');
  });

  Future<int> mode(String name) async => (await file(name).stat()).mode & 0x1ff;

  Future<void> chmod(String name, String bits) async {
    final r = await Process.run('chmod', [bits, file(name).path]);
    if (r.exitCode != 0) throw StateError('chmod failed: ${r.stderr}');
  }

  test('undo puts the executable bit back', () async {
    await g(['config', 'core.fileMode', 'true']);
    await chmod('a.txt', '755');
    await g(['commit', '-q', '-am', 'exec']);
    final exec = await g(['rev-parse', 'HEAD']);
    await file('a.txt').writeAsString('exec working\n');
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));

    // Same mode on both sides: undo leaves no mode change behind.
    await actions.restoreFileVersion(exec, 'a.txt');
    await actions.undo();
    expect(await file('a.txt').readAsString(), 'exec working\n');
    expect(await mode('a.txt'), 0x1ed);
    expect(await g(['diff', '--summary']), isNot(contains('mode change')));

    // The restore drops the bit; undo brings it back.
    await actions.restoreFileVersion(v1, 'a.txt');
    expect(await mode('a.txt'), 0x1a4);
    await actions.undo();
    expect(await mode('a.txt'), 0x1ed);
  }, skip: Platform.isWindows ? 'no POSIX modes' : false);

  test('a git that fails is reported, not thrown', () async {
    final c = container(git: _NoGit());

    await c.read(repoActionsProvider(dir.path)).restoreFileVersion(v1, 'a.txt');

    expect(c.read(toastProvider).last.kind, ToastKind.error);
    expect(await file('a.txt').readAsString(), 'v2\n');
  });

  test('a revision git cannot read is an error, not a missing file', () async {
    final c = container();

    await c
        .read(repoActionsProvider(dir.path))
        .restoreFileVersion('0' * 40, 'a.txt');

    expect(c.read(toastProvider).last.kind, ToastKind.error);
    expect(await file('a.txt').readAsString(), 'v2\n');
  });

  test('a path the commit lacks changes nothing and warns', () async {
    await file('b.txt').writeAsString('mine\n');
    await Directory('${dir.path}/sub').create();
    await file('sub/c.txt').writeAsString('c\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'later']);
    final c = container();
    final actions = c.read(repoActionsProvider(dir.path));

    // Restoring from a commit without the path would delete the file.
    await actions.restoreFileVersion(v1, 'b.txt');
    expect(await file('b.txt').readAsString(), 'mine\n');
    expect(c.read(toastProvider).last.kind, ToastKind.warning);
    expect(c.read(toastProvider).last.title, contains('does not exist'));

    // A directory is not a file version either.
    await actions.restoreFileVersion('HEAD', 'sub');
    expect(await file('sub/c.txt').readAsString(), 'c\n');
    expect(c.read(toastProvider).last.title, contains('not a file'));

    expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
  });
}
