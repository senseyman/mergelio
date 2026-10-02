import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/review.dart';

class _FakeForge implements Forge {
  final List<PullRequest> prs;
  final bool fail;
  final asked = <String>[];
  _FakeForge(this.prs, {this.fail = false});

  @override
  ForgeHost get host => const ForgeHost(
    kind: ForgeKind.github,
    host: 'github.com',
    owner: 'o',
    repo: 'r',
  );

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async {
    asked.add(branch);
    if (fail) throw const ForgeOffline('down');
    return prs;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PullRequest _pr(int n, String target) => PullRequest(
  number: n,
  title: 't',
  state: PullRequestState.open,
  author: const ForgeUser(login: 'u'),
  sourceBranch: 'feature',
  targetBranch: target,
  headSha: 'abc',
);

void main() {
  group('ReviewTarget', () {
    const t = ReviewTarget(repoPath: '/r', base: 'main', head: 'feature');

    test('defaults to three-dot and names its range', () {
      expect(t.threeDot, isTrue);
      expect(t.range, 'main...feature');
      expect(t.withThreeDot(false).range, 'main..feature');
    });

    test('swapping keeps the mode', () {
      final s = t.withThreeDot(false).swapped;
      expect((s.base, s.head, s.threeDot), ('feature', 'main', false));
    });

    test('equality covers every field', () {
      expect(
        t,
        const ReviewTarget(repoPath: '/r', base: 'main', head: 'feature'),
      );
      expect(t, isNot(t.withThreeDot(false)));
      expect(t, isNot(t.swapped));
    });
  });

  group('viewed marks', () {
    const t = ReviewTarget(repoPath: '/r', base: 'main', head: 'feature');

    test('a mark holds only while the diff is unchanged', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final viewed = c.read(reviewViewedProvider(t).notifier);

      viewed.toggle('a.txt', 'fp1');
      expect(isViewed(c.read(reviewViewedProvider(t)), 'a.txt', 'fp1'), isTrue);
      // Head moved and the file's diff changed under the tick.
      expect(
        isViewed(c.read(reviewViewedProvider(t)), 'a.txt', 'fp2'),
        isFalse,
      );

      viewed.toggle('a.txt', 'fp1');
      expect(
        isViewed(c.read(reviewViewedProvider(t)), 'a.txt', 'fp1'),
        isFalse,
      );
    });

    test('toggling a stale mark re-marks the current content', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final viewed = c.read(reviewViewedProvider(t).notifier);
      viewed.toggle('a.txt', 'old');
      viewed.toggle('a.txt', 'new');
      expect(isViewed(c.read(reviewViewedProvider(t)), 'a.txt', 'new'), isTrue);
    });

    test('marks belong to one review', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(reviewViewedProvider(t).notifier).toggle('a.txt', 'fp');
      expect(
        isViewed(c.read(reviewViewedProvider(t.swapped)), 'a.txt', 'fp'),
        isFalse,
      );
    });

    test('setAll marks and clears a batch', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final viewed = c.read(reviewViewedProvider(t).notifier);
      viewed.setAll({'a': '1', 'b': '2'}, viewed: true);
      expect(c.read(reviewViewedProvider(t)), {'a': '1', 'b': '2'});
      viewed.setAll({'a': '1'}, viewed: false);
      expect(c.read(reviewViewedProvider(t)), {'b': '2'});
    });
  });

  group('reviewSummaryProvider (real git)', () {
    late Directory repo;
    const svc = SystemGitService();

    Future<String> g(List<String> args) async {
      final r = await svc.run(args, repoPath: repo.path);
      if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
      return r.out;
    }

    Future<void> commit(String path, String body, String msg) async {
      await File('${repo.path}/$path').writeAsString(body);
      await g(['add', '-A']);
      await g(['commit', '-q', '-m', msg]);
    }

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('mergelio_rvstate_');
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@e.com']);
      await g(['config', 'user.name', 'T']);
      await g(['config', 'commit.gpgsign', 'false']);
      await commit('a.txt', 'one\n', 'base');
      await g(['checkout', '-q', '-b', 'feature']);
      await commit('a.txt', 'one\ntwo\n', 'f1');
      await g(['checkout', '-q', 'main']);
      await commit('m.txt', 'm\n', 'm1');
    });

    tearDown(() async {
      if (await repo.exists()) await repo.delete(recursive: true);
    });

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(svc),
          // The summary follows ref moves through repo data; nothing moves in
          // these tests.
          repoDataProvider.overrideWith((ref, p) async => const RepoData()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('three-dot reads files from the merge base', () async {
      final c = container();
      final t = ReviewTarget(
        repoPath: repo.path,
        base: 'main',
        head: 'feature',
      );
      final s = await c.read(reviewSummaryProvider(t).future);
      final mb = await g(['merge-base', 'main', 'feature']);

      expect(s.mergeBase, mb);
      expect(s.fromRev, mb);
      expect(s.headSha, await g(['rev-parse', 'feature']));
      expect((s.counts.ahead, s.counts.behind), (1, 1));
      expect([for (final x in s.commits) x.message], ['f1']);
      expect([for (final f in s.files) f.path], ['a.txt']);
    });

    test('two-dot reads files from base\'s tip', () async {
      final c = container();
      final t = ReviewTarget(
        repoPath: repo.path,
        base: 'main',
        head: 'feature',
        threeDot: false,
      );
      final s = await c.read(reviewSummaryProvider(t).future);
      expect(s.fromRev, await g(['rev-parse', 'main']));
      expect({for (final f in s.files) f.path}, {'a.txt', 'm.txt'});
    });

    test('unrelated histories have no three-dot answer', () async {
      await g(['checkout', '-q', '--orphan', 'lonely']);
      await g(['rm', '-rq', '--cached', '.']);
      await commit('z.txt', 'z\n', 'root');
      final c = container();
      final t = ReviewTarget(repoPath: repo.path, base: 'main', head: 'lonely');
      final s = await c.read(reviewSummaryProvider(t).future);
      expect(s.mergeBase, isNull);
      expect(s.fromRev, isNull);
      expect(s.files, isEmpty);
    });

    test('the whole diff is read once and keyed by path', () async {
      final c = container();
      final t = ReviewTarget(
        repoPath: repo.path,
        base: 'main',
        head: 'feature',
      );
      final s = await c.read(reviewSummaryProvider(t).future);
      final diffs = await c.read(
        reviewDiffProvider((
          repoPath: repo.path,
          from: s.fromRev!,
          to: s.headSha,
        )).future,
      );
      expect(diffs.keys, ['a.txt']);
      expect(diffs['a.txt']!.hunks.single.lines.last.text, 'two');
    });
  });

  group('reviewPullRequestProvider', () {
    ProviderContainer container(Forge? forge) {
      final c = ProviderContainer(
        overrides: [
          forgeProvider.overrideWith((ref, p) async => forge),
          repoDataProvider.overrideWith(
            (ref, p) async => const RepoData(
              branches: [
                Branch(name: 'main'),
                Branch(name: 'feature'),
              ],
              remotes: ['origin'],
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    const t = ReviewTarget(repoPath: '/r', base: 'main', head: 'feature');

    test('finds the request for head aimed at base', () async {
      final forge = _FakeForge([_pr(3, 'dev'), _pr(7, 'main')]);
      final c = container(forge);
      final found = await c.read(reviewPullRequestProvider(t).future);
      expect(found?.pr.number, 7);
      expect(found?.host.repo, 'r');
      expect(forge.asked, ['feature']);
    });

    test('a remote head is looked up by its branch name', () async {
      final forge = _FakeForge([_pr(1, 'main')]);
      final c = container(forge);
      await c.read(
        reviewPullRequestProvider(
          const ReviewTarget(repoPath: '/r', base: 'main', head: 'origin/x'),
        ).future,
      );
      expect(forge.asked, ['x']);
    });

    test(
      'no forge, a tag head or a forge failure all mean no button',
      () async {
        expect(
          await container(null).read(reviewPullRequestProvider(t).future),
          isNull,
        );
        final forge = _FakeForge([_pr(1, 'main')]);
        expect(
          await container(forge).read(
            reviewPullRequestProvider(
              const ReviewTarget(repoPath: '/r', base: 'main', head: 'v1.0'),
            ).future,
          ),
          isNull,
        );
        expect(forge.asked, isEmpty);
        expect(
          await container(_FakeForge([_pr(1, 'main')], fail: true))
              .read(reviewPullRequestProvider(t).future),
          isNull,
        );
      },
    );
  });
}
