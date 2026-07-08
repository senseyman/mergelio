import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_service.dart';
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
    dir = await Directory.systemTemp.createTemp('mergelio_ident_');
    await g(['init', '-q', '-b', 'main']);
    // Repo default identity (should be overridden by the active profile).
    await g(['config', 'user.email', 'repo@default.com']);
    await g(['config', 'user.name', 'Repo Default']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('commit uses the active profile identity', () async {
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            const ProfilesState(
              profiles: [
                Profile(
                  id: '1',
                  name: 'Maria K',
                  email: 'maria@work.com',
                  colorValue: 0xFF112233,
                ),
              ],
              activeId: '1',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await File('${dir.path}/a.txt').writeAsString('x\n');
    final actions = container.read(repoActionsProvider(dir.path));
    await actions.stageAll();
    await actions.commit('first');

    final author = (await svc.run([
      'log',
      '-1',
      '--format=%an <%ae>',
    ], repoPath: dir.path)).out;
    expect(author, 'Maria K <maria@work.com>');
  });
}
