import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

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

  test('creates pr/<n> at the pull request head and checks it out', () async {
    final pr = await publish('refs/pull/7/head', base, 'pr 7');

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('pr/7'), pr);
    expect(await head(), 'pr/7');
    expect(toasts().where((t) => t.kind == ToastKind.error), isEmpty);
  });

  test('a gitlab merge request lands on mr/<n>', () async {
    final mr = await publish('refs/merge-requests/3/head', base, 'mr 3');

    await actions().checkoutPullRequest(ForgeKind.gitlab, 3);

    expect(await tip('mr/3'), mr);
    expect(await head(), 'mr/3');
  });

  test('fast-forwards an existing pr/<n> the request moved past', () async {
    final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
    await g(['branch', 'pr/7', first]);
    final second = await publish('refs/pull/7/head', first, 'pr 7 v2');

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('pr/7'), second);
    expect(await head(), 'pr/7');
  });

  test('leaves a diverged pr/<n> alone and says so', () async {
    final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
    await g(['branch', 'pr/7', first]);
    // Local work on the branch, and a force-push on the forge.
    await g(['checkout', '-q', 'pr/7']);
    await g(['commit', '-q', '--allow-empty', '-m', 'local work']);
    final local = await g(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', 'main']);
    await publish('refs/pull/7/head', base, 'pr 7 rewritten');

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('pr/7'), local);
    expect(await head(), 'main');
    expect(toasts().last.kind, ToastKind.error);
  });

  test('already on pr/<n>, fast-forwards it in place', () async {
    final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
    await g(['checkout', '-q', '-b', 'pr/7', first]);
    final second = await publish('refs/pull/7/head', first, 'pr 7 v2');
    await g(['checkout', '-q', 'pr/7']);

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('pr/7'), second);
    expect(await head(), 'pr/7');
    expect(toasts().where((t) => t.kind == ToastKind.error), isEmpty);
  });

  test('already on a diverged pr/<n>, makes no commit and says so', () async {
    final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
    await g(['checkout', '-q', '-b', 'pr/7', first]);
    await g(['commit', '-q', '--allow-empty', '-m', 'local work']);
    final local = await g(['rev-parse', 'HEAD']);
    await g(['checkout', '-q', 'main']);
    await publish('refs/pull/7/head', first, 'pr 7 v2');
    await g(['checkout', '-q', 'pr/7']);

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    // Never a merge commit: the branch is exactly where it was.
    expect(await tip('pr/7'), local);
    expect(await head(), 'pr/7');
    expect(toasts().last.kind, ToastKind.error);
  });

  test(
    'a pull.rebase preference cannot turn the update into a rebase',
    () async {
      final first = await publish('refs/pull/7/head', base, 'pr 7 v1');
      await g(['checkout', '-q', '-b', 'pr/7', first]);
      await g(['commit', '-q', '--allow-empty', '-m', 'local work']);
      final local = await g(['rev-parse', 'HEAD']);
      await g(['checkout', '-q', 'main']);
      await publish('refs/pull/7/head', first, 'pr 7 v2');
      await g(['checkout', '-q', 'pr/7']);
      await g(['config', 'pull.rebase', 'true']);

      await actions().checkoutPullRequest(ForgeKind.github, 7);

      // A rebase would rewrite the local commit onto the request's new head.
      expect(await tip('pr/7'), local);
    },
  );

  test('a request origin does not have creates nothing', () async {
    await actions().checkoutPullRequest(ForgeKind.github, 99);

    expect(await tip('pr/99'), isNull);
    expect(await head(), 'main');
    expect(toasts().last.kind, ToastKind.error);
  });

  test('does not touch the branch origin calls main', () async {
    await publish('refs/pull/7/head', base, 'pr 7');

    await actions().checkoutPullRequest(ForgeKind.github, 7);

    expect(await tip('main'), base);
  });
}
