// The graph's own load lays stashes out without lanes for their snapshots.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/state/repo_data.dart';

import 'support/hermetic_git.dart';

void main() {
  late Directory dir;
  const git = HermeticGit();

  Future<void> g(List<String> args) async {
    final r = await git.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_stash_lanes_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    for (final n in ['1', '2']) {
      await File('${dir.path}/a.txt').writeAsString('$n\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', n]);
    }
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a stash with untracked files leaves no lane open below it', () async {
    await File('${dir.path}/a.txt').writeAsString('changed\n');
    await File('${dir.path}/new.txt').writeAsString('untracked\n');
    await g(['stash', 'push', '-q', '-u', '-m', 'wip']);

    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    final data = await c.read(repoDataProvider(dir.path).future);

    final last = data.commits.last;
    expect({...last.through}..remove(last.lane), isEmpty);
    expect(data.commits.every((c) => c.lane == 0), isTrue);
  });
}
