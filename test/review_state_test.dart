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
  final limits = <int>[];
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
    limits.add(limit);
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
      expect([for (final f in s.files) f.change.path], ['a.txt']);
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
      expect({for (final f in s.files) f.change.path}, {'a.txt', 'm.txt'});
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

    test('one file\'s diff is read on its own', () async {
      final c = container();
      final t = ReviewTarget(
        repoPath: repo.path,
        base: 'main',
        head: 'feature',
      );
      final s = await c.read(reviewSummaryProvider(t).future);
      final diff = await c.read(
        reviewFileDiffProvider((
          repoPath: repo.path,
          from: s.fromRev!,
          to: s.headSha,
          path: 'a.txt',
          origPath: null,
        )).future,
      );
      expect(diff!.hunks.single.lines.last.text, 'two');
    });

    test('unrelated histories still list head\'s commits', () async {
      await g(['checkout', '-q', '--orphan', 'lonely']);
      await g(['rm', '-rq', '--cached', '.']);
      await commit('z.txt', 'z\n', 'root');
      final c = container();
      final t = ReviewTarget(repoPath: repo.path, base: 'main', head: 'lonely');
      final s = await c.read(reviewSummaryProvider(t).future);
      expect([for (final x in s.commits) x.message], ['root']);
    });
  });

  group('pull request lookup', () {
    const host = ForgeHost(
      kind: ForgeKind.github,
      host: 'github.com',
      owner: 'o',
      repo: 'r',
    );

    ProviderContainer container({ForgeHost? forgeHost = host}) {
      final c = ProviderContainer(
        overrides: [
          forgeHostProvider.overrideWith((ref, p) async => forgeHost),
          // Building a forge is what leads to the network; the query must
          // never get that far.
          forgeProvider.overrideWith(
            (ref, p) async => throw StateError('forge asked on open'),
          ),
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

    test('the query names both branches without asking the forge', () async {
      final q = await container().read(reviewPrQueryProvider(t).future);
      expect((q?.host, q?.head, q?.base), (host, 'feature', 'main'));
    });

    test('a remote head is looked up by its branch name', () async {
      final q = await container().read(
        reviewPrQueryProvider(
          const ReviewTarget(repoPath: '/r', base: 'main', head: 'origin/x'),
        ).future,
      );
      expect(q?.head, 'x');
    });

    test('no forge or a tag head means nothing to look up', () async {
      expect(
        await container(forgeHost: null).read(reviewPrQueryProvider(t).future),
        isNull,
      );
      expect(
        await container().read(
          reviewPrQueryProvider(
            const ReviewTarget(repoPath: '/r', base: 'main', head: 'v1.0'),
          ).future,
        ),
        isNull,
      );
    });

    test(
      'lookup asks once, within the usual page, and picks base\'s',
      () async {
        final forge = _FakeForge([_pr(3, 'dev'), _pr(7, 'main')]);
        final pr = await lookUpReviewPullRequest(forge, (
          host: host,
          head: 'feature',
          base: 'main',
        ));
        expect(pr?.number, 7);
        expect(forge.asked, ['feature']);
        expect(forge.limits, [kPullRequestLimit]);
      },
    );

    test('a forge failure reaches the caller', () async {
      expect(
        () => lookUpReviewPullRequest(_FakeForge(const [], fail: true), (
          host: host,
          head: 'feature',
          base: 'main',
        )),
        throwsA(isA<ForgeError>()),
      );
    });
  });
}
