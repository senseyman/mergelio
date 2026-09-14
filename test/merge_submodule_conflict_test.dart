import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

/// A conflicted submodule is a gitlink, not text: there is nothing in the
/// worktree to parse markers from, and writing a file over the directory would
/// destroy the checkout. It resolves by picking which commit to point at.
void main() {
  const svc = SystemGitService();
  late Directory parent;
  late Directory child;

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  Future<String> sha(Directory d, String ref) async =>
      (await svc.run(['rev-parse', ref], repoPath: d.path)).out;

  Future<void> initRepo(Directory d) async {
    await g(d, ['init', '-q', '-b', 'main']);
    await g(d, ['config', 'user.email', 't@e.com']);
    await g(d, ['config', 'user.name', 'T']);
    await g(d, ['config', 'commit.gpgsign', 'false']);
  }

  late String base;
  late String ours;
  late String theirs;

  setUp(() async {
    // Two divergent commits in the submodule: neither is an ancestor of the
    // other, so merging the superproject cannot fast-forward the gitlink.
    child = await Directory.systemTemp.createTemp('mergelio_subconf_child_');
    await initRepo(child);
    await File('${child.path}/c.txt').writeAsString('base\n');
    await g(child, ['add', '.']);
    await g(child, ['commit', '-q', '-m', 'base']);
    base = await sha(child, 'HEAD');
    await g(child, ['checkout', '-q', '-b', 'x']);
    await File('${child.path}/c.txt').writeAsString('x\n');
    await g(child, ['commit', '-q', '-am', 'x']);
    theirs = await sha(child, 'HEAD');
    await g(child, ['checkout', '-q', base]);
    await g(child, ['checkout', '-q', '-b', 'y']);
    await File('${child.path}/c.txt').writeAsString('y\n');
    await g(child, ['commit', '-q', '-am', 'y']);
    ours = await sha(child, 'HEAD');

    parent = await Directory.systemTemp.createTemp('mergelio_subconf_parent_');
    await initRepo(parent);
    await g(parent, ['config', 'protocol.file.allow', 'always']);
    await g(parent, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      '-q',
      child.path,
      'sub',
    ]);
    // The submodule is added at its current HEAD; pin the superproject to the
    // shared base so each branch moves it somewhere different.
    await g(parent, ['-C', 'sub', 'checkout', '-q', base]);
    await g(parent, ['add', 'sub']);
    await g(parent, ['commit', '-q', '-m', 'add sub']);

    await g(parent, ['checkout', '-q', '-b', 'feature']);
    await g(parent, ['-C', 'sub', 'checkout', '-q', theirs]);
    await g(parent, ['commit', '-q', '-am', 'sub theirs']);
    await g(parent, ['checkout', '-q', 'main']);
    await g(parent, ['-C', 'sub', 'checkout', '-q', ours]);
    await g(parent, ['commit', '-q', '-am', 'sub ours']);
  });

  tearDown(() async {
    for (final d in [parent, child]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('a conflicted submodule opens as a whole-file choice', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(parent.path)).merge('feature');

    final session = c.read(mergeSessionProvider(parent.path));
    expect(session, isNotNull);
    final sub = session!.files.single;
    expect(sub.path, 'sub');
    expect(sub.submodule, isTrue);
    expect(sub.wholeFile, isTrue);
    expect(session.allResolved, isFalse);
  });

  test('keeping our side leaves the submodule checkout intact', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(parent.path));
    await actions.merge('feature');

    final session = c.read(mergeSessionProvider(parent.path))!;
    await actions.resolveConflicts(
      session.withFiles([
        for (final f in session.files) f.withFileChoice(FileResolution.ours),
      ]),
    );

    expect(await GitReader(svc, parent.path).conflictedFiles(), isEmpty);
    // Still a checked-out submodule, not a file written over the directory.
    expect(await Directory('${parent.path}/sub').exists(), isTrue);
    expect(await File('${parent.path}/sub/c.txt').readAsString(), 'y\n');
    expect(
      (await svc.run([
        'ls-files',
        '-s',
        '--',
        'sub',
      ], repoPath: parent.path)).out,
      contains(ours),
    );
  });

  test('keeping their side moves the gitlink to their commit', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(parent.path));
    await actions.merge('feature');

    final session = c.read(mergeSessionProvider(parent.path))!;
    await actions.resolveConflicts(
      session.withFiles([
        for (final f in session.files) f.withFileChoice(FileResolution.theirs),
      ]),
    );

    expect(await GitReader(svc, parent.path).conflictedFiles(), isEmpty);
    expect(
      (await svc.run([
        'ls-files',
        '-s',
        '--',
        'sub',
      ], repoPath: parent.path)).out,
      contains(theirs),
    );
    // The submodule's own checkout follows the gitlink it was pointed at.
    expect(await File('${parent.path}/sub/c.txt').readAsString(), 'x\n');
  });
}
