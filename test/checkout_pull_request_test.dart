import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/pull_request_ref.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/undo_stack.dart';

import 'support/hermetic_git.dart';

/// Checking out a pull request against a real repository whose origin is a
/// local bare repository carrying forge-style `refs/pull/*` and
/// `refs/merge-requests/*` refs, as GitHub and GitLab publish them.
void main() {
  late Directory dir;
  late String repo;
  late String remote;
  late String base;
  late ProviderContainer c;

  Future<String> g(List<String> args, {String? at}) async {
    final r = await const HermeticGit().run(args, repoPath: at ?? repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out.trim();
  }

  /// Publishes a commit on top of [parent] as [ref] on origin, the way a
  /// forge does for a pull request's head, and returns its sha. The commit
  /// is made on a throwaway branch that is deleted again, so locally it is
  /// reachable from nothing.
  Future<String> publish(String ref, String parent, String message) async {
    await g(['branch', 'tmp-publish', parent]);
    await g(['checkout', '-q', 'tmp-publish']);
    await g(['commit', '-q', '--allow-empty', '-m', message]);
    final sha = await g(['rev-parse', 'HEAD']);
    // Forced: a forge rewrites a request's head on every force-push.
    await g(['push', '-q', '--force', 'origin', 'HEAD:$ref']);
    await g(['checkout', '-q', 'main']);
    await g(['branch', '-q', '-D', 'tmp-publish']);
    return sha;
  }

  Future<String> head() => g(['rev-parse', '--abbrev-ref', 'HEAD']);
  Future<String?> tip(String branch) async {
    final r = await const HermeticGit().run([
      'rev-parse',
      '--verify',
      '-q',
      'refs/heads/$branch',
    ], repoPath: repo);
    return r.ok ? r.out.trim() : null;
  }

  List<Toast> toasts() => c.read(toastProvider);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_pr_checkout_');
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
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(const HermeticGit()),
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
  Future<void> undo() => c.read(undoProvider(repo).notifier).undo();
  Future<void> redo() => c.read(undoProvider(repo).notifier).redo();
  Iterable<Toast> errors() => toasts().where((t) => t.kind == ToastKind.error);

  /// A local pr/7 at the request's first head plus one commit of its own,
  /// and a request force-pushed to something else: the two have diverged.
  /// Returns (local tip, new request head).
  Future<(String, String)> diverge({
    bool checkedOut = false,
    String? from,
  }) async {
    final root = from ?? base;
    final first = await publish('refs/pull/7/head', root, 'pr 7 v1');
    await g(['checkout', '-q', '-b', 'pr/7', first]);
    await g(['commit', '-q', '--allow-empty', '-m', 'local work']);
    final local = await g(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', 'main']);
    final rewritten = await publish('refs/pull/7/head', root, 'rewritten');
    if (checkedOut) await g(['checkout', '-q', 'pr/7']);
    return (local, rewritten);
  }

  group('a request with no local branch yet', () {
    test('creates pr/<n> at its head and checks it out', () async {
      final pr = await publish('refs/pull/7/head', base, 'pr 7');

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.done);
      expect(await tip('pr/7'), pr);
      expect(await head(), 'pr/7');
      expect(errors(), isEmpty);
      // Only the request's branch is written; the fetch itself names no
      // local ref.
      expect(
        await g(['for-each-ref', '--format=%(refname)', 'refs/heads']),
        'refs/heads/main\nrefs/heads/pr/7',
      );
    });

    test('takes the sha of exactly that ref, not one ending like it', () async {
      // ls-remote matches by tail, so a branch whose name ends in the same
      // components would answer too — and sorts first.
      final decoy = await publish(
        'refs/heads/decoy/refs/pull/7/head',
        base,
        'decoy',
      );
      final pr = await publish('refs/pull/7/head', base, 'pr 7');
      expect(decoy, isNot(pr));

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(await tip('pr/7'), pr);
    });

    test('a gitlab merge request lands on mr/<n>', () async {
      final mr = await publish('refs/merge-requests/3/head', base, 'mr 3');

      await actions().checkoutPullRequest(ForgeKind.gitlab, 3);

      expect(await tip('mr/3'), mr);
      expect(await head(), 'mr/3');
    });

    test('puts the cursor on the request and re-reads LFS state', () async {
      final pr = await publish('refs/pull/7/head', base, 'pr 7');
      final lfsBefore = c.read(lfsGenerationProvider(repo));

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(c.read(selectedCommitProvider), pr);
      expect(c.read(lfsGenerationProvider(repo)), greaterThan(lfsBefore));
    });

    test('undo returns to the prior branch and removes pr/<n>', () async {
      final pr = await publish('refs/pull/7/head', base, 'pr 7');
      await actions().checkoutPullRequest(ForgeKind.github, 7);

      await undo();
      expect(await head(), 'main');
      expect(await tip('pr/7'), isNull);

      await redo();
      expect(await head(), 'pr/7');
      expect(await tip('pr/7'), pr);
    });

    test('a checkout git refuses leaves no pr/<n> behind', () async {
      await File('$repo/f.txt').writeAsString('base\n');
      await g(['add', 'f.txt']);
      await g(['commit', '-q', '-m', 'f']);
      await g(['push', '-q', 'origin', 'main']);
      final main = await g(['rev-parse', 'HEAD']);
      await File('$repo/f.txt').writeAsString('request\n');
      await g(['commit', '-q', '-am', 'request edits f']);
      await g(['push', '-q', '--force', 'origin', 'HEAD:refs/pull/7/head']);
      await g(['reset', '-q', '--hard', main]);
      // An uncommitted edit the checkout would have to overwrite.
      await File('$repo/f.txt').writeAsString('mine\n');

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.failed);
      expect(await tip('pr/7'), isNull);
      expect(await head(), 'main');
      expect(await File('$repo/f.txt').readAsString(), 'mine\n');
      expect(errors(), isNotEmpty);
    });
  });

  group('an existing pr/<n>', () {
    test('fast-forwards when the request moved on', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['branch', 'pr/7', first]);
      final second = await publish('refs/pull/7/head', first, 'pr 7 v2');

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(await tip('pr/7'), second);
      expect(await head(), 'pr/7');
      expect(c.read(selectedCommitProvider), second);
    });

    test('undo of a fast-forward puts the old tip back', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['branch', 'pr/7', first]);
      await publish('refs/pull/7/head', first, 'pr 7 v2');
      await actions().checkoutPullRequest(ForgeKind.github, 7);

      await undo();

      expect(await head(), 'main');
      expect(await tip('pr/7'), first);
    });

    test('diverged: reports it and touches nothing', () async {
      final (local, _) = await diverge();

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.diverged);
      // The request's old head and the local commit: the rewrite dropped
      // both.
      expect(r.localOnly, 2);
      expect(await tip('pr/7'), local);
      expect(await head(), 'main');
      // Not an error: the caller asks whether to replace.
      expect(errors(), isEmpty);
    });

    test(
      'diverged, replace: moves to the request head; undo restores',
      () async {
        final (local, rewritten) = await diverge();

        final r = await actions().checkoutPullRequest(
          ForgeKind.github,
          7,
          replace: true,
        );

        expect(r.outcome, PullRequestCheckoutOutcome.done);
        expect(await tip('pr/7'), rewritten);
        expect(await head(), 'pr/7');

        await undo();
        expect(await tip('pr/7'), local);
        expect(await head(), 'main');
      },
    );

    test('held by another worktree: git refuses, nothing moves', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['branch', 'pr/7', first]);
      await g(['worktree', 'add', '-q', '${dir.path}/wt', 'pr/7']);
      await publish('refs/pull/7/head', first, 'pr 7 v2');

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.failed);
      expect(await tip('pr/7'), first);
      expect(await head(), 'main');
      expect(errors(), isNotEmpty);
    });
  });

  group('already on pr/<n>', () {
    test('fast-forwards it in place', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['checkout', '-q', '-b', 'pr/7', first]);
      final second = await publish('refs/pull/7/head', first, 'pr 7 v2');
      await g(['checkout', '-q', 'pr/7']);

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(await tip('pr/7'), second);
      expect(await head(), 'pr/7');
      expect(c.read(selectedCommitProvider), second);
      expect(errors(), isEmpty);
    });

    test('keeps uncommitted work across the fast-forward', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['checkout', '-q', '-b', 'pr/7', first]);
      await publish('refs/pull/7/head', first, 'pr 7 v2');
      await File('$repo/scratch.txt').writeAsString('wip\n');
      await g(['add', 'scratch.txt']);

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(await g(['diff', '--cached', '--name-only']), 'scratch.txt');
    });

    test('says so when it is already up to date', () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7');
      await g(['checkout', '-q', '-b', 'pr/7', first]);

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.done);
      expect(toasts().last.kind, ToastKind.info);
      expect(toasts().last.title, contains('pr/7'));
    });

    test('diverged: reports it and makes no commit', () async {
      final (local, _) = await diverge(checkedOut: true);

      final r = await actions().checkoutPullRequest(ForgeKind.github, 7);

      expect(r.outcome, PullRequestCheckoutOutcome.diverged);
      expect(await tip('pr/7'), local);
      expect(await g(['rev-list', '--count', 'HEAD']), '3');
    });

    test('diverged, replace: keeps uncommitted work; undo restores', () async {
      // A tracked file both sides share, edited and not committed: what a
      // hard reset would silently throw away.
      await File('$repo/keep.txt').writeAsString('committed\n');
      await g(['add', 'keep.txt']);
      await g(['commit', '-q', '-m', 'keep']);
      final root = await g(['rev-parse', 'HEAD']);
      final (local, rewritten) = await diverge(checkedOut: true, from: root);
      await File('$repo/keep.txt').writeAsString('edited\n');

      await actions().checkoutPullRequest(ForgeKind.github, 7, replace: true);

      expect(await tip('pr/7'), rewritten);
      expect(await head(), 'pr/7');
      expect(await File('$repo/keep.txt').readAsString(), 'edited\n');

      await undo();
      expect(await tip('pr/7'), local);
      expect(await File('$repo/keep.txt').readAsString(), 'edited\n');
    });
  });

  group('a request origin does not have', () {
    test('creates nothing and says which request', () async {
      final r = await actions().checkoutPullRequest(ForgeKind.github, 99);

      expect(r.outcome, PullRequestCheckoutOutcome.failed);
      expect(await tip('pr/99'), isNull);
      expect(await head(), 'main');
      expect(errors().single.title, contains('#99'));
    });

    test('on gitlab names the merge request its own way', () async {
      final r = await actions().checkoutPullRequest(ForgeKind.gitlab, 4);

      expect(r.outcome, PullRequestCheckoutOutcome.failed);
      expect(await tip('mr/4'), isNull);
      expect(errors().single.title, contains('!4'));
    });
  });

  test('never moves the branch origin calls main', () async {
    await publish('refs/pull/7/head', base, 'pr 7');

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('main'), base);
  });
}
