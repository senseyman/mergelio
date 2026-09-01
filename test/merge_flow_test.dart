import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_mflow_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await g(['checkout', '-q', '-b', 'feature']);
    await File('${dir.path}/a.txt').writeAsString('feature\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'feature']);
    await g(['checkout', '-q', 'main']);
    await File('${dir.path}/a.txt').writeAsString('main\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'main']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test(
    'conflicting merge opens a session; resolving stages it for review',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      await actions.merge('feature');

      var session = c.read(mergeSessionProvider(dir.path));
      expect(session, isNotNull);
      expect(session!.files.single.path, 'a.txt');
      expect(session.allResolved, isFalse);

      // Resolve every hunk to theirs, then hand the session back.
      var file = session.files.single;
      for (final h in file.hunkIndices) {
        file = file.withResolution(h, Resolution.theirs);
      }
      session = session.replaceFile(0, file);
      c.read(mergeSessionProvider(dir.path).notifier).state = session;
      expect(session.allResolved, isTrue);

      await actions.resolveConflicts(session);

      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(await GitReader(svc, dir.path).conflictedFiles(), isEmpty);
      expect(await File('${dir.path}/a.txt').readAsString(), 'feature\n');

      // The merge is staged, not committed — the user commits it.
      await actions.commit('Merge feature');
      expect(
        (await svc.run(['rev-parse', 'HEAD^2'], repoPath: dir.path)).ok,
        isTrue,
      );
    },
  );

  test('a finished merge commit is attributed to the active profile', () async {
    final c = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            const ProfilesState(
              profiles: [
                Profile(
                  id: '1',
                  label: 'Work',
                  name: 'Alice',
                  email: 'alice@work.com',
                  colorValue: 0xFF112233,
                ),
              ],
              activeId: '1',
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await actions.merge('feature');
    var session = c.read(mergeSessionProvider(dir.path))!;
    var file = session.files.single;
    for (final h in file.hunkIndices) {
      file = file.withResolution(h, Resolution.theirs);
    }
    await actions.resolveConflicts(session.replaceFile(0, file));
    await actions.commit('Merge feature');

    final author = (await svc.run([
      'log',
      '-1',
      '--format=%an <%ae>',
    ], repoPath: dir.path)).out;
    expect(author, 'Alice <alice@work.com>');
  });

  test('aborting a merge clears the session and restores the tree', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await actions.merge('feature');
    expect(c.read(mergeSessionProvider(dir.path)), isNotNull);

    await actions.abortMerge();
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
    expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
  });
}
