import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

/// A modify/delete or binary conflict has no `<<<<<<<` markers to pick
/// between. The session must still offer a resolution — keep a side, or drop
/// the path — instead of stranding the user in the terminal.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  List<int> bytes(int seed) => [0x00, seed, 0x00, seed, 0x01, 0x02];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_wfile_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/doc.txt').writeAsString('base\n');
    await File('${dir.path}/doc2.txt').writeAsString('renamed later\n');
    await File('${dir.path}/logo.bin').writeAsBytes(bytes(1));
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    await g(['checkout', '-q', '-b', 'feature']);
    await File('${dir.path}/doc.txt').delete();
    await File('${dir.path}/logo.bin').writeAsBytes(bytes(2));
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', 'feature']);

    await g(['checkout', '-q', 'main']);
    await File('${dir.path}/doc.txt').writeAsString('mine\n');
    await File('${dir.path}/logo.bin').writeAsBytes(bytes(3));
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', 'main']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ConflictFile fileNamed(MergeSession s, String path) =>
      s.files.firstWhere((f) => f.path == path);

  test('a modify/delete conflict opens as a whole-file choice', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).merge('feature');

    final session = c.read(mergeSessionProvider(dir.path));
    expect(session, isNotNull);
    final doc = fileNamed(session!, 'doc.txt');
    expect(doc.kind, ConflictKind.deletedByThem);
    expect(doc.wholeFile, isTrue);
    expect(doc.fileOptions, [FileResolution.ours, FileResolution.delete]);
    expect(session.allResolved, isFalse);
  });

  test('a binary conflict opens as a whole-file choice', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).merge('feature');

    final logo = fileNamed(c.read(mergeSessionProvider(dir.path))!, 'logo.bin');
    expect(logo.binary, isTrue);
    expect(logo.wholeFile, isTrue);
    expect(logo.parts, isEmpty);
  });

  test('keeping their side stages their content', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await actions.merge('feature');

    var session = c.read(mergeSessionProvider(dir.path))!;
    session = session.withFiles([
      for (final f in session.files)
        f.path == 'doc.txt'
            ? f.withFileChoice(FileResolution.ours)
            : f.withFileChoice(FileResolution.theirs),
    ]);
    expect(session.allResolved, isTrue);
    await actions.resolveConflicts(session);

    expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    expect(await File('${dir.path}/doc.txt').readAsString(), 'mine\n');
    expect(await File('${dir.path}/logo.bin').readAsBytes(), bytes(2));
    // Staged, ready for the user's merge commit.
    expect(
      (await svc.run([
        'diff',
        '--cached',
        '--name-only',
      ], repoPath: dir.path)).out,
      contains('logo.bin'),
    );
  });

  test('deleting resolves a modify/delete conflict', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await actions.merge('feature');

    var session = c.read(mergeSessionProvider(dir.path))!;
    session = session.withFiles([
      for (final f in session.files) f.withFileChoice(FileResolution.delete),
    ]);
    await actions.resolveConflicts(session);

    expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    expect(await File('${dir.path}/doc.txt').exists(), isFalse);
    expect(await File('${dir.path}/logo.bin').exists(), isFalse);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
  });

  test('a rename/rename conflict offers each side what it still has', () async {
    // Both branches renamed the same file somewhere else: the old path is
    // deleted on both sides, and each new path exists on one side only.
    await g(['checkout', '-q', 'feature']);
    await g(['mv', 'doc2.txt', 'theirs.txt']);
    await g(['commit', '-q', '-m', 'rename theirs']);
    await g(['checkout', '-q', 'main']);
    await g(['mv', 'doc2.txt', 'ours.txt']);
    await g(['commit', '-q', '-m', 'rename ours']);

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await actions.merge('feature');

    var session = c.read(mergeSessionProvider(dir.path))!;
    expect(fileNamed(session, 'ours.txt').kind, ConflictKind.addedByUs);
    expect(fileNamed(session, 'ours.txt').fileOptions, [
      FileResolution.ours,
      FileResolution.delete,
    ]);
    expect(fileNamed(session, 'theirs.txt').kind, ConflictKind.addedByThem);
    expect(fileNamed(session, 'doc2.txt').kind, ConflictKind.bothDeleted);
    expect(fileNamed(session, 'doc2.txt').fileOptions, [FileResolution.delete]);

    session = session.withFiles([
      for (final f in session.files)
        f.withFileChoice(switch (f.path) {
          'ours.txt' => FileResolution.ours,
          'theirs.txt' => FileResolution.theirs,
          _ => FileResolution.delete,
        }),
    ]);
    await actions.resolveConflicts(session);

    expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    expect(await File('${dir.path}/ours.txt').exists(), isTrue);
    expect(await File('${dir.path}/theirs.txt').exists(), isTrue);
    expect(await File('${dir.path}/doc2.txt').exists(), isFalse);
  });

  test('a text conflict beside a binary one still resolves by hunk', () async {
    await g(['checkout', '-q', 'feature']);
    await File('${dir.path}/shared.txt').writeAsString('theirs\n');
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', 'feature text']);
    await g(['checkout', '-q', 'main']);
    await File('${dir.path}/shared.txt').writeAsString('mine\n');
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', 'main text']);

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));
    await actions.merge('feature');

    var session = c.read(mergeSessionProvider(dir.path))!;
    final shared = fileNamed(session, 'shared.txt');
    expect(shared.wholeFile, isFalse);
    expect(shared.total, 1);

    session = session.withFiles([
      for (final f in session.files)
        f.wholeFile
            ? f.withFileChoice(FileResolution.delete)
            : f.withResolution(f.hunkIndices.single, Resolution.theirs),
    ]);
    await actions.resolveConflicts(session);

    expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
    expect(await File('${dir.path}/shared.txt').readAsString(), 'theirs\n');
  });
}
