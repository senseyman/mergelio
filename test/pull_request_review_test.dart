import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/review.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

import 'support/fake_forge.dart';
import 'support/hermetic_git.dart';

const _github = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

const _pr = PullRequest(
  number: 7,
  title: 'Add the thing',
  state: PullRequestState.open,
  author: ForgeUser(login: 'ann'),
  sourceBranch: 'feature/x',
  targetBranch: 'main',
  headSha: 'h',
);

/// [HermeticGit] that records every command, and can run [beforeFetch] once,
/// just before the first `git fetch` — which is where a remote moving under
/// the caller would land.
class _ObservedGit implements GitService {
  final calls = <List<String>>[];
  Future<void> Function()? beforeFetch;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    if (args.isNotEmpty && args.first == 'fetch') {
      final hook = beforeFetch;
      beforeFetch = null;
      await hook?.call();
    }
    return const HermeticGit().run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
      stdin: stdin,
    );
  }

  @override
  Future<String> version() => const HermeticGit().version();

  @override
  Future<bool> isRepository(String path) =>
      const HermeticGit().isRepository(path);
}

void main() {
  group('ReviewTarget for a pull request', () {
    const pr = ReviewPullRequest(
      kind: ForgeKind.github,
      number: 7,
      targetBranch: 'main',
    );
    const t = ReviewTarget(
      repoPath: '/r',
      base: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      head: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      pullRequest: pr,
    );

    test('names its sides after the request, not the fetched commits', () {
      expect(t.baseLabel, 'main');
      expect(t.headLabel, '#7');
      expect(t.range, 'main...#7');
    });

    test('a merge request is spelled the way GitLab spells it', () {
      const mr = ReviewTarget(
        repoPath: '/r',
        base: 'b',
        head: 'h',
        pullRequest: ReviewPullRequest(
          kind: ForgeKind.gitlab,
          number: 7,
          targetBranch: 'main',
        ),
      );
      expect(mr.headLabel, '!7');
    });

    test('switching the mode keeps the request', () {
      expect(t.withThreeDot(false).pullRequest, pr);
    });

    test('swapping leaves the request behind', () {
      // Base against the request is no longer what the request proposes, so
      // its description and CI would describe something not on screen.
      final s = t.swapped;
      expect(s.pullRequest, isNull);
      expect((s.base, s.head), (t.head, t.base));
    });

    test('equality covers the request', () {
      expect(
        t,
        isNot(
          const ReviewTarget(
            repoPath: '/r',
            base: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            head: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
      );
      expect(
        t,
        const ReviewTarget(
          repoPath: '/r',
          base: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          head: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          pullRequest: ReviewPullRequest(
            kind: ForgeKind.github,
            number: 7,
            targetBranch: 'main',
          ),
        ),
      );
    });
  });

  group('forge reads for a pull request review', () {
    ProviderContainer container(FakeForge forge) {
      final c = ProviderContainer(
        overrides: [forgeProvider.overrideWith((ref, _) async => forge)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the detail comes from the forge by number', () async {
      final forge = FakeForge(
        host: _github,
        details: {7: const PullRequestDetail(request: _pr, body: 'hi')},
      );
      final c = container(forge);

      final d = await c.read(
        pullRequestDetailProvider((repoPath: '/r', number: 7, head: 'h'))
            .future,
      );

      expect(d?.body, 'hi');
      expect(forge.pullRequestCalls, 1);
    });

    test('a forge failure reaches the reader', () async {
      final c = container(
        FakeForge(host: _github, pullRequestError: const ForgeOffline('x')),
      );
      final sub = c.listen(
        pullRequestDetailProvider((repoPath: '/r', number: 7, head: 'h')),
        (_, _) {},
      );
      addTearDown(sub.close);

      await expectLater(
        c.read(
          pullRequestDetailProvider((repoPath: '/r', number: 7, head: 'h'))
              .future,
        ),
        throwsA(isA<ForgeOffline>()),
      );
    });

    test('checks are read for the reviewed commit', () async {
      final forge = FakeForge(
        host: _github,
        checks: ChecksSummary.from(const [
          CheckRun(name: 'build', state: CheckState.success),
          CheckRun(name: 'lint', state: CheckState.failure),
        ]),
      );
      final c = container(forge);

      final s = await c.read(
        pullRequestChecksProvider((repoPath: '/r', sha: 'a' * 40)).future,
      );

      expect(forge.checkedRefs, ['a' * 40]);
      expect(s?.runs.map((r) => r.name), ['build', 'lint']);
    });

    test('a repository on no forge has nothing to read', () async {
      final c = ProviderContainer(
        overrides: [forgeProvider.overrideWith((ref, _) async => null)],
      );
      addTearDown(c.dispose);

      expect(
        await c.read(
          pullRequestDetailProvider((repoPath: '/r', number: 7, head: 'h'))
              .future,
        ),
        isNull,
      );
      expect(
        await c.read(
          pullRequestChecksProvider((repoPath: '/r', sha: 'a' * 40)).future,
        ),
        isNull,
      );
    });
  });

  group('fetching a pull request for review (real git)', () {
    late Directory dir;
    late String repo;
    late String remote;
    late String other;
    late String base;
    late ProviderContainer c;
    late _ObservedGit git;

    Future<String> g(List<String> args, {String? at}) async {
      final r = await const HermeticGit().run(args, repoPath: at ?? repo);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
      return r.out.trim();
    }

    /// Publishes a commit on top of [parent] as [ref] on origin and returns
    /// its sha. Made in a separate clone, so this repository has never seen
    /// its objects — as with a request someone else pushed.
    Future<String> publish(String ref, String parent, String message) async {
      await g(['checkout', '-q', '--detach', parent], at: other);
      await g(['commit', '-q', '--allow-empty', '-m', message], at: other);
      final sha = await g(['rev-parse', 'HEAD'], at: other);
      await g(['push', '-q', '--force', 'origin', 'HEAD:$ref'], at: other);
      return sha;
    }

    Future<bool> has(String sha) async => (await const HermeticGit().run([
      'cat-file',
      '-e',
      '$sha^{commit}',
    ], repoPath: repo)).ok;

    // Names and values: a fetch that moved origin/main would keep every name.
    Future<String> refs() =>
        g(['for-each-ref', '--format=%(refname) %(objectname)']);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mergelio_pr_review_');
      repo = '${dir.path}/r';
      remote = '${dir.path}/remote.git';
      await Directory(repo).create();
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 'a@b.c']);
      await g(['config', 'user.name', 'A']);
      await g(['commit', '-q', '--allow-empty', '-m', 'base']);
      base = await g(['rev-parse', 'HEAD']);
      await g(['init', '-q', '--bare', remote], at: dir.path);
      await g(['remote', 'add', 'origin', remote]);
      await g(['push', '-q', 'origin', 'main']);
      other = '${dir.path}/other';
      await g(['clone', '-q', remote, other], at: dir.path);
      await g(['config', 'user.email', 'o@b.c'], at: other);
      await g(['config', 'user.name', 'O'], at: other);
      git = _ObservedGit();
      c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      c.dispose();
      await dir.delete(recursive: true);
    });

    RepoActions actions() => c.read(repoActionsProvider(repo));
    Iterable<Toast> errors() =>
        c.read(toastProvider).where((t) => t.kind == ToastKind.error);
    String errorText() =>
        errors().map((t) => '${t.title} ${t.description ?? ''}').join('\n');

    test('brings in head and target tip, and writes no ref', () async {
      final head = await publish('refs/pull/7/head', base, 'pr 7');
      // origin's main has moved on since this clone last fetched it, which
      // is what a review must read against.
      final target = await publish('refs/heads/main', base, 'upstream work');
      final before = await refs();
      expect(await has(head), isFalse);
      expect(await has(target), isFalse);

      final r = await actions().fetchPullRequestForReview(
        ForgeKind.github,
        7,
        'main',
      );

      expect(r, (base: target, head: head));
      expect(await has(head), isTrue);
      expect(await has(target), isTrue);
      expect(await refs(), before);
      expect(errors(), isEmpty);
    });

    test(
      'leaves remote-tracking refs where they were, even mapped ones',
      () async {
        // A fetch refspec mapping request heads is a common setup; git would
        // update such a ref, and origin/main, on any fetch naming them.
        await g([
          'config',
          '--add',
          'remote.origin.fetch',
          '+refs/pull/*/head:refs/remotes/origin/pr/*',
        ]);
        await publish('refs/pull/7/head', base, 'pr 7');
        await publish('refs/heads/main', base, 'upstream work');
        final before = await refs();

        final r = await actions().fetchPullRequestForReview(
          ForgeKind.github,
          7,
          'main',
        );

        expect(r, isNotNull);
        expect(await refs(), before);
      },
    );

    test('fetches nothing when both commits are already here', () async {
      final head = await publish('refs/pull/7/head', base, 'pr 7');
      // Already downloaded once, the way an earlier review would have.
      await g(['fetch', '-q', '--refmap=', 'origin', 'refs/pull/7/head']);
      expect(await has(head), isTrue);

      final r = await actions().fetchPullRequestForReview(
        ForgeKind.github,
        7,
        'main',
      );

      expect(r, (base: base, head: head));
      expect(git.calls.where((a) => a.first == 'fetch'), isEmpty);
    });

    test(
      'a request pushed to while opening is reported, not half-opened',
      () async {
        // ls-remote names one head; by the time it is fetched the request
        // points at another, so the commit read first never arrives.
        await publish('refs/pull/7/head', base, 'pr 7 v1');
        git.beforeFetch = () => publish('refs/pull/7/head', base, 'pr 7 v2');

        final r = await actions().fetchPullRequestForReview(
          ForgeKind.github,
          7,
          'main',
        );

        expect(r, isNull);
        expect(
          errorText(),
          contains('The request changed while it was being opened.'),
        );
      },
    );

    test('reads a merge request from where GitLab publishes it', () async {
      final head = await publish('refs/merge-requests/3/head', base, 'mr 3');

      final r = await actions().fetchPullRequestForReview(
        ForgeKind.gitlab,
        3,
        'main',
      );

      expect(r?.head, head);
      expect(r?.base, base);
    });

    test('a request origin does not carry fails, and says so', () async {
      final r = await actions().fetchPullRequestForReview(
        ForgeKind.github,
        9,
        'main',
      );

      expect(r, isNull);
      expect(errors(), isNotEmpty);
    });

    test('a target branch origin does not carry fails, and says so', () async {
      await publish('refs/pull/7/head', base, 'pr 7');

      final r = await actions().fetchPullRequestForReview(
        ForgeKind.github,
        7,
        'gone',
      );

      expect(r, isNull);
      expect(errorText(), contains('origin has no branch gone'));
    });

    test('an unusable target name is refused before git is asked', () async {
      // The name came from the forge; with a colon it would be a refspec
      // that writes a local branch.
      final head = await publish('refs/pull/7/head', base, 'pr 7');
      final before = await refs();

      final r = await actions().fetchPullRequestForReview(
        ForgeKind.github,
        7,
        'main:refs/heads/planted',
      );

      expect(r, isNull);
      // Refused by name, not by origin happening to lack such a branch.
      expect(
        errorText(),
        contains('The request targets a branch name git cannot fetch.'),
      );
      expect(await refs(), before);
      expect(await has(head), isFalse);
    });
  });
}
