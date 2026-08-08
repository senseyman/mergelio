import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';

/// Integration tests: build a real repository with the system `git` binary and
/// read it back through [GitReader].
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_reader_');
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);

    await write('a.txt', '1\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'A']);

    await g(['checkout', '-q', '-b', 'feature']);
    await write('b.txt', 'b\n');
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'B on feature']);

    await g(['checkout', '-q', 'main']);
    await write('a.txt', '2\n');
    await g(['add', 'a.txt']);
    await g(['commit', '-q', '-m', 'C on main']);

    await g(['merge', '--no-ff', '-m', 'Merge feature', 'feature']);
    await g(['tag', 'v1.0']);

    // Working-tree state: one staged add, one unstaged modify, one untracked.
    await write('d.txt', 'd\n');
    await g(['add', 'd.txt']);
    await write('a.txt', '3\n');
    await write('e.txt', 'untracked\n');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  GitReader reader() => GitReader(svc, dir.path);

  test("keeps the author's UTC offset alongside the instant", () async {
    await g([
      'commit',
      '--allow-empty',
      '-q',
      '-m',
      'Zoned',
      '--date=2026-07-02T14:33:00+05:30',
    ]);
    final head = (await reader().commits()).first;
    expect(head.message, 'Zoned');
    expect(head.dateOffset, const Duration(hours: 5, minutes: 30));
    // The instant itself is unchanged: 14:33 at +05:30 is 09:03 UTC.
    expect(head.date.toUtc(), DateTime.utc(2026, 7, 2, 9, 3));
  });

  test(
    'a commit authored west of Greenwich carries a negative offset',
    () async {
      await g([
        'commit',
        '--allow-empty',
        '-q',
        '-m',
        'Western',
        '--date=2026-07-02T09:00:00-08:00',
      ]);
      final head = (await reader().commits()).first;
      expect(head.dateOffset, const Duration(hours: -8));
    },
  );

  test('reads commits with a two-parent merge and ref decoration', () async {
    final commits = await reader().commits();
    expect(commits, isNotEmpty);

    final merge = commits.firstWhere((c) => c.merge);
    expect(merge.parents.length, 2);
    expect(merge.message, 'Merge feature');

    final hasMainHead = commits.any(
      (c) => c.refs.any((r) => r.kind == RefKind.local && r.name == 'main'),
    );
    expect(hasMainHead, isTrue);
  });

  test(
    'captures the multi-line commit body separately from the subject',
    () async {
      await g([
        'commit',
        '--allow-empty',
        '-q',
        '-m',
        'Subject line',
        '-m',
        'First body paragraph.\n\nSecond paragraph.',
      ]);
      final head = (await reader().commits()).first;
      expect(head.message, 'Subject line');
      expect(head.body, 'First body paragraph.\n\nSecond paragraph.');
    },
  );

  test('a commit with no body has an empty body string', () async {
    final root = (await reader().commits()).firstWhere(
      (c) => c.parents.isEmpty,
    );
    expect(root.body, isEmpty);
  });

  test('assignLanes places the merge and gives it mergeFrom', () async {
    final laned = assignLanes(await reader().commits());
    final merge = laned.firstWhere((c) => c.merge);
    expect(merge.mergeFrom, isNotNull);
    expect(laned.any((c) => c.lane > 0), isTrue);
  });

  test('reads local branches with current flag', () async {
    final branches = await reader().branches();
    final names = branches.map((b) => b.name).toSet();
    expect(names, containsAll(<String>['main', 'feature']));
    expect(branches.firstWhere((b) => b.name == 'main').current, isTrue);
    expect(branches.firstWhere((b) => b.name == 'feature').current, isFalse);
  });

  test('reads the upstream ref of a tracking branch', () async {
    // Point feature at main as its upstream, leave main untracked.
    await g(['branch', '--set-upstream-to=main', 'feature']);
    final branches = await reader().branches();
    expect(branches.firstWhere((b) => b.name == 'feature').upstream, 'main');
    expect(branches.firstWhere((b) => b.name == 'main').upstream, '');
  });

  test('reads tags', () async {
    expect(await reader().tags(), contains('v1.0'));
  });

  test('lists files changed by a commit', () async {
    final commits = await reader().commits();
    final root = commits.firstWhere((c) => c.parents.isEmpty);
    final merge = commits.firstWhere((c) => c.merge);

    final rootFiles = await reader().commitFiles(root.sha);
    expect(rootFiles, hasLength(1));
    expect(rootFiles.single.path, 'a.txt');
    expect(rootFiles.single.change, GitChange.added);

    // A merge shows its first-parent diff: only what the merged branch brought
    // in (b.txt), never files that changed solely on the mainline (a.txt was
    // modified by 'C on main', which is the merge's first parent).
    final mergeFiles = await reader().commitFiles(merge.sha);
    expect(mergeFiles.map((f) => f.path), ['b.txt']);
  });

  test('parses staged, unstaged and untracked working files', () async {
    final files = {for (final f in await reader().status()) f.path: f};

    expect(files['d.txt']?.isStaged, isTrue);
    expect(files['a.txt']?.isUnstaged, isTrue);
    expect(files['e.txt']?.isUntracked, isTrue);
  });

  test(
    'lists files inside a wholly-untracked directory individually',
    () async {
      await Directory('${dir.path}/imgs').create();
      await write('imgs/one.png', 'a\n');
      await write('imgs/two.png', 'b\n');

      final paths = {for (final f in await reader().status()) f.path};

      // git collapses an entirely-untracked directory to a single 'imgs/' entry
      // unless all untracked files are requested; the tree must see each file.
      expect(paths, containsAll(['imgs/one.png', 'imgs/two.png']));
      expect(paths, isNot(contains('imgs/')));
    },
  );

  test('stashes carry their commit sha and appear in the graph', () async {
    // Two stashes on top of the existing repo.
    await write('a.txt', 'stash-one\n');
    await g(['stash', 'push', '-q', '-m', 'one']);
    await write('a.txt', 'stash-two\n');
    await g(['stash', 'push', '-q', '-m', 'two']);

    final stashes = await reader().stashes();
    expect(stashes, hasLength(2));
    expect(stashes.every((s) => s.sha.isNotEmpty), isTrue);

    final shas = (await reader().commits()).map((c) => c.sha).toSet();
    // Every stash node (including the older stash@{1}) is in the graph.
    expect(shas, containsAll(stashes.map((s) => s.sha)));
  });

  test(
    'a stash internal index/untracked commits are not graph nodes',
    () async {
      await write('a.txt', 'changed\n');
      await write('extra.txt', 'untracked\n');
      await g(['stash', 'push', '-q', '-u', '-m', 'with-untracked']);

      final stashSha = (await reader().stashes()).first.sha;
      final shas = (await reader().commits()).map((c) => c.sha).toSet();
      expect(shas, contains(stashSha)); // the stash itself shows

      // rev-list --parents: '<stash> <base> <index> <untracked>'. The index and
      // untracked snapshot commits must not appear as graph nodes.
      final parents = (await svc.run(
        ['rev-list', '--no-walk', '--parents', stashSha],
        repoPath: dir.path,
      )).out.split(' ').where((s) => s.isNotEmpty).toList();
      final aux = parents.skip(2).toList(); // skip stash sha + base parent
      expect(aux, isNotEmpty);
      for (final a in aux) {
        expect(shas, isNot(contains(a)));
      }
    },
  );

  group('squashLinks', () {
    late Directory sdir;

    Future<void> sg(List<String> args) async {
      final r = await svc.run(args, repoPath: sdir.path);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    Future<void> swrite(String name, String content) =>
        File('${sdir.path}/$name').writeAsString(content);

    setUp(() async {
      sdir = await Directory.systemTemp.createTemp('mergelio_squash_');
      await sg(['init', '-q']);
      await sg(['symbolic-ref', 'HEAD', 'refs/heads/main']);
      await sg(['config', 'user.email', 't@example.com']);
      await sg(['config', 'user.name', 'Tester']);
      await sg(['config', 'commit.gpgsign', 'false']);

      await swrite('base.txt', 'base\n');
      await sg(['add', '.']);
      await sg(['commit', '-q', '-m', 'base']);

      await sg(['checkout', '-q', '-b', 'feature']);
      await swrite('f1.txt', '1\n');
      await sg(['add', '.']);
      await sg(['commit', '-q', '-m', 'feat 1']);
      await swrite('f2.txt', '2\n');
      await sg(['add', '.']);
      await sg(['commit', '-q', '-m', 'feat 2']);

      // Squash-merge feature onto main: one new commit, no parent edge.
      await sg(['checkout', '-q', 'main']);
      await sg(['merge', '--squash', 'feature']);
      await sg(['commit', '-q', '-m', 'Squash feature (#1)']);

      // An unrelated open branch that was NOT merged — must not be linked.
      await sg(['checkout', '-q', '-b', 'open']);
      await swrite('o.txt', 'o\n');
      await sg(['add', '.']);
      await sg(['commit', '-q', '-m', 'open work']);
      await sg(['checkout', '-q', 'main']);
    });

    tearDown(() async {
      if (await sdir.exists()) await sdir.delete(recursive: true);
    });

    test('links a squash-merged branch tip to its landing commit', () async {
      final r = GitReader(svc, sdir.path);
      final branches = await r.branches();
      final links = await r.squashLinks(branches, into: 'main');

      final featureTip = (await svc.run([
        'rev-parse',
        'feature',
      ], repoPath: sdir.path)).out;
      final landing = (await svc.run([
        'rev-parse',
        'main',
      ], repoPath: sdir.path)).out;

      expect(links, hasLength(1));
      expect(links.single.fromSha, featureTip);
      expect(links.single.toSha, landing);
    });

    test('does not link an open, unmerged branch', () async {
      final r = GitReader(svc, sdir.path);
      final branches = await r.branches();
      final links = await r.squashLinks(branches, into: 'main');
      final openTip = (await svc.run([
        'rev-parse',
        'open',
      ], repoPath: sdir.path)).out;
      expect(links.map((l) => l.fromSha), isNot(contains(openTip)));
    });
  });
}
