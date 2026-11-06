// The background CI / pull-request watcher: it runs only while the window is
// unfocused, reads only repos whose notifications want it, holds off a host
// whose budget runs low, and turns what changed into desktop notifications.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/forge_notify.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/notification_prefs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/window_focus.dart';
import 'package:mergelio/state/workspace.dart';

import 'support/fake_desktop_notifier.dart';
import 'support/fake_forge.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);
const _path = '/work/repo';

PullRequest _pr(int n, {PullRequestState state = PullRequestState.open}) =>
    PullRequest(
      number: n,
      title: 'Change $n',
      state: state,
      author: const ForgeUser(login: 'a'),
      sourceBranch: 'topic-$n',
      targetBranch: 'main',
      headSha: 'h$n',
    );

const _success = ChecksSummary(overall: ChecksOverall.success);
const _running = ChecksSummary(overall: ChecksOverall.running);

/// A workspace whose tabs a test sets outright, so the same path can sit in
/// two tabs the way two repo groups can both hold it.
class _Workspace extends WorkspaceController {
  _Workspace(List<String> paths) {
    state = WorkspaceState(
      tabs: [
        for (var i = 0; i < paths.length; i++)
          RepoTab(id: i + 1, name: 'repo', path: paths[i]),
      ],
      activeTabId: paths.isEmpty ? null : 1,
    );
  }
}

class _Harness {
  final ProviderContainer c;
  final FakeForge forge;
  final FakeDesktopNotifier notifier;
  final List<PullRequest> prs;
  ForgeRateLimit? limit;
  DateTime now = DateTime(2026, 11, 6, 12);

  _Harness(this.c, this.forge, this.notifier, this.prs);

  ForgeNotifyWatcher get watcher => c.read(forgeNotifyWatcherProvider);
  List<String> get bodies => [for (final n in notifier.shown) n.body];

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

_Harness _harness({
  bool ci = true,
  bool pullRequests = true,
  bool focused = false,
  List<String> tabs = const [_path],
  List<PullRequest>? prs,
  Map<int, PullRequestDetail> details = const {},
}) {
  final list = [
    ...(prs ?? [_pr(10)]),
  ];
  final forge = FakeForge(
    host: _host,
    pullRequests: list,
    checks: _running,
    details: {...details},
  );
  final notifier = FakeDesktopNotifier();
  late final _Harness h;
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          AppSettings(
            notificationsEnabled: true,
            notifyCi: ci,
            notifyPullRequests: pullRequests,
            forgeRefreshIntervalSeconds: 120,
          ),
        ),
      ),
      kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      desktopNotifierProvider.overrideWithValue(notifier),
      windowFocusedProvider.overrideWith((ref) => focused),
      workspaceProvider.overrideWith((ref) => _Workspace(tabs)),
      forgeHostProvider.overrideWith((ref, path) async => _host),
      forgeRefreshEligibleProvider.overrideWith((ref, path) async => true),
      forgeProvider.overrideWith((ref, path) async => forge),
      forgeRateLimitProvider.overrideWith((ref, path) async => h.limit),
      repoDataProvider.overrideWith(
        (ref, path) async => const RepoData(
          branches: [
            Branch(
              name: 'feature',
              current: true,
              tip: 'l1',
              upstream: 'origin/feature',
            ),
          ],
          remoteBranches: [
            RemoteBranch(remote: 'origin', branch: 'feature', tip: 'u1'),
          ],
        ),
      ),
      forgeNotifyWatcherProvider.overrideWith(
        (ref) => ForgeNotifyWatcher(ref, now: () => h.now),
      ),
    ],
  );
  addTearDown(c.dispose);
  h = _Harness(c, forge, notifier, list);
  return h;
}

void main() {
  test('the first tick only seeds; a new request after it notifies', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();

    await w.tick();
    expect(h.notifier.shown, isEmpty);
    expect(w.snapshots.keys, [_path]);

    h.prs.add(_pr(11));
    await w.tick();

    expect(h.bodies, ['PR #11 opened: Change 11']);
  });

  test(
    'CI is read for every head and the upstream until it is final',
    () async {
      final h = _harness(prs: [_pr(10), _pr(11)]);
      final w = h.watcher;
      await h.settle();

      await w.tick();
      expect(h.forge.checkedRefs.toSet(), {'h10', 'h11', 'u1'});

      h.forge.checksBySha['u1'] = _success;
      await w.tick();
      h.forge.checkedRefs.clear();
      await w.tick();

      expect(h.forge.checkedRefs, isNot(contains('u1')));
      expect(h.forge.checkedRefs.toSet(), {'h10', 'h11'});
    },
  );

  test('a finished upstream run notifies under the current branch', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();

    await w.tick();
    h.forge.checksBySha['u1'] = _success;
    await w.tick();

    expect(h.bodies, ['CI passed on feature']);
  });

  test('a repo with CI and requests off is never read', () async {
    final h = _harness(ci: false, pullRequests: false);
    final w = h.watcher;
    await h.settle();

    await w.tick();
    await w.tick();

    expect(h.forge.pullRequestsCalls, 0);
    expect(w.snapshots, isEmpty);
  });

  test('the timer runs only while the window is unfocused', () async {
    final h = _harness(focused: true);
    final w = h.watcher;
    await h.settle();
    expect(w.scheduledInterval, isNull);

    h.c.read(windowFocusedProvider.notifier).state = false;
    await h.settle();
    expect(w.scheduledInterval, const Duration(seconds: 120));
    expect(
      h.forge.pullRequestsCalls,
      0,
      reason: 'losing focus must not tick at once',
    );

    h.c.read(windowFocusedProvider.notifier).state = true;
    await h.settle();
    expect(w.scheduledInterval, isNull);
  });

  test('a tick while focused reads nothing and keeps the snapshot', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();
    await w.tick();
    h.c.read(windowFocusedProvider.notifier).state = true;
    await h.settle();

    await w.tick();

    expect(h.forge.pullRequestsCalls, 1);
    expect(w.snapshots.keys, [_path]);
  });

  test('a low budget holds the host off until its reset', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();
    h.limit = ForgeRateLimit(
      remaining: 999,
      limit: 5000,
      resetAt: h.now.add(const Duration(hours: 1)),
    );

    await w.tick();
    expect(h.forge.pullRequestsCalls, 0);
    expect(h.forge.checksCalls, 0);

    h.now = h.now.add(const Duration(hours: 1, seconds: 1));
    await w.tick();
    expect(h.forge.pullRequestsCalls, 1);
  });

  test(
    'a low budget whose reset already passed reads on the next tick',
    () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      h.limit = ForgeRateLimit(
        remaining: 999,
        limit: 5000,
        resetAt: h.now.subtract(const Duration(minutes: 1)),
      );

      await w.tick();
      expect(h.forge.pullRequestsCalls, 0);
      await w.tick();
      expect(h.forge.pullRequestsCalls, 1);
    },
  );

  test('a merged request says merged; one still open says nothing', () async {
    final h = _harness(
      prs: [_pr(10), _pr(11)],
      details: {
        10: PullRequestDetail(request: _pr(10, state: PullRequestState.merged)),
        11: PullRequestDetail(request: _pr(11)),
      },
    );
    final w = h.watcher;
    await h.settle();

    await w.tick();
    h.prs.clear();
    await w.tick();

    expect(h.bodies, ['PR #10 merged']);
    expect(h.forge.pullRequestCalls, 2);
  });

  group('review focus', () {
    test('one path in two tabs is read and notified once', () async {
      final h = _harness(tabs: [_path, _path]);
      final w = h.watcher;
      await h.settle();

      await w.tick();
      expect(h.forge.pullRequestsCalls, 1);

      h.prs.add(_pr(11));
      await w.tick();
      expect(h.forge.pullRequestsCalls, 2);
      expect(h.notifier.shown, hasLength(1));
    });

    test('a low budget without a reset time pauses exactly one tick', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      h.limit = const ForgeRateLimit(remaining: 999, limit: 5000);

      await w.tick();
      expect(h.forge.pullRequestsCalls, 0);

      h.now = h.now.add(w.scheduledInterval!);
      await w.tick();
      expect(h.forge.pullRequestsCalls, 1);
    });

    test(
      'an unauthorised list read backs off silently, then resumes',
      () async {
        final h = _harness();
        final w = h.watcher;
        await h.settle();
        await w.tick();
        final seeded = w.snapshots[_path];

        h.forge.pullRequestsError = const ForgeUnauthenticated();
        h.prs.add(_pr(11));
        await w.tick();

        expect(h.notifier.shown, isEmpty);
        expect(h.c.read(toastProvider), isEmpty);
        expect(w.scheduledInterval, const Duration(seconds: 240));
        expect(w.snapshots[_path], same(seeded));

        h.forge.pullRequestsError = null;
        await w.tick();

        expect(h.bodies, ['PR #11 opened: Change 11']);
        expect(w.scheduledInterval, const Duration(seconds: 120));
      },
    );

    test('turning requests off and on again re-seeds silently', () async {
      final h = _harness(ci: false);
      final w = h.watcher;
      await h.settle();
      await w.tick();
      expect(w.snapshots.keys, [_path]);

      final settings = h.c.read(settingsProvider.notifier);
      settings.setNotify(NotifyEvent.pullRequests, false);
      await h.settle();
      await w.tick();
      expect(w.snapshots, isEmpty);

      h.prs.add(_pr(12));
      settings.setNotify(NotifyEvent.pullRequests, true);
      await h.settle();
      await w.tick();

      expect(h.notifier.shown, isEmpty);
      expect(w.snapshots.keys, [_path]);
    });
  });
}
