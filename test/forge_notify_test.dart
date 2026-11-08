// The background CI / pull-request watcher: it runs only while the window is
// unfocused, reads only repos whose notifications want it, holds off a host
// whose budget runs low, and turns what changed into desktop notifications.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/forge_notify.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/notification_gate.dart';
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
const _failure = ChecksSummary(overall: ChecksOverall.failure);
const _none = ChecksSummary(overall: ChecksOverall.none);

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

/// Records which event kind each notification was routed through, then lets
/// the real gate decide as usual.
class _RecordingGate extends NotificationGate {
  _RecordingGate(super.ref, this.kinds);
  final List<NotifyEvent> kinds;

  @override
  Future<bool> notify(NotifyEvent e, AppNotification n) {
    kinds.add(e);
    return super.notify(e, n);
  }
}

class _CountingStore extends InMemoryKeyValueStore {
  int gets = 0;
  @override
  Future<String?> get(String key) {
    gets++;
    return super.get(key);
  }
}

class _Harness {
  final ProviderContainer c;
  final FakeForge forge;
  final FakeDesktopNotifier notifier;
  final List<PullRequest> prs;
  ForgeRateLimit? limit;
  final List<NotifyEvent> kinds = [];
  DateTime now = DateTime(2026, 11, 6, 12);

  /// How often each forge-facing provider was built, and how many reads the
  /// key-value store saw: a watcher with nothing to do must touch none.
  final Map<String, int> reads = {};
  final _CountingStore kv = _CountingStore();

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
  bool master = true,
  bool ci = true,
  bool pullRequests = true,
  bool focused = false,
  List<String> tabs = const [_path],
  List<PullRequest>? prs,
  Map<int, PullRequestDetail> details = const {},
  String upstreamRemote = 'origin',
  Future<ForgeHost?> Function(String path)? hostFor,
  Future<ForgeRateLimit?> Function(String path)? limitFor,
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
  void count(String what) => h.reads[what] = (h.reads[what] ?? 0) + 1;
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          AppSettings(
            notificationsEnabled: master,
            notifyCi: ci,
            notifyPullRequests: pullRequests,
            forgeRefreshIntervalSeconds: 120,
          ),
        ),
      ),
      kvStoreProvider.overrideWith((ref) => h.kv),
      desktopNotifierProvider.overrideWithValue(notifier),
      windowFocusedProvider.overrideWith((ref) => focused),
      workspaceProvider.overrideWith((ref) => _Workspace(tabs)),
      forgeHostProvider.overrideWith((ref, path) {
        count('host');
        return hostFor?.call(path) ?? Future.value(_host);
      }),
      forgeRefreshEligibleProvider.overrideWith((ref, path) async {
        count('eligible');
        return true;
      }),
      forgeProvider.overrideWith((ref, path) async {
        count('forge');
        return forge;
      }),
      forgeRateLimitProvider.overrideWith((ref, path) {
        count('budget');
        return limitFor?.call(path) ?? Future.value(h.limit);
      }),
      notificationGateProvider.overrideWith(
        (ref) => _RecordingGate(ref, h.kinds),
      ),
      repoDataProvider.overrideWith(
        (ref, path) async => RepoData(
          branches: [
            Branch(
              name: 'feature',
              current: true,
              tip: 'l1',
              upstream: '$upstreamRemote/feature',
            ),
          ],
          remoteBranches: [
            RemoteBranch(remote: upstreamRemote, branch: 'feature', tip: 'u1'),
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
  // Failed reads are logged on purpose; keep that out of the test output.
  final realDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = realDebugPrint);

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

  group('CI re-checks', () {
    int reads(_Harness h, String sha) =>
        h.forge.checkedRefs.where((r) => r == sha).length;

    test('a final result is read again every third tick', () async {
      final h = _harness();
      h.forge.checksBySha['h10'] = _failure;
      final w = h.watcher;
      await h.settle();

      await w.tick();
      expect(reads(h, 'h10'), 1);

      // A re-run on the same commit goes green.
      h.forge.checksBySha['h10'] = _success;
      await w.tick();
      await w.tick();
      expect(reads(h, 'h10'), 1);
      expect(h.notifier.shown, isEmpty);

      await w.tick();
      expect(reads(h, 'h10'), 2);
      expect(h.bodies, ['CI passed on topic-10 (PR #10)']);
    });

    test('failure, success, failure on one commit notifies each', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();

      h.forge.checksBySha['h10'] = _failure;
      await w.tick();
      h.forge.checksBySha['h10'] = _success;
      for (var i = 0; i < 3; i++) {
        await w.tick();
      }
      h.forge.checksBySha['h10'] = _failure;
      for (var i = 0; i < 3; i++) {
        await w.tick();
      }

      expect(h.bodies, [
        'CI failed on topic-10 (PR #10)',
        'CI passed on topic-10 (PR #10)',
        'CI failed on topic-10 (PR #10)',
      ]);
    });

    test('a re-run seen running between two finals notifies once', () async {
      final h = _harness();
      h.forge.checksBySha['h10'] = _success;
      final w = h.watcher;
      await h.settle();
      await w.tick();

      h.forge.checksBySha['h10'] = _running;
      for (var i = 0; i < 3; i++) {
        await w.tick();
      }
      h.forge.checksBySha['h10'] = _success;
      await w.tick();

      expect(h.bodies, ['CI passed on topic-10 (PR #10)']);
    });

    test('a commit with no CI settles after two reads', () async {
      final h = _harness();
      h.forge.checksBySha['h10'] = _none;
      final w = h.watcher;
      await h.settle();

      await w.tick();
      await w.tick();
      expect(reads(h, 'h10'), 2);

      await w.tick();
      await w.tick();
      expect(reads(h, 'h10'), 2);

      await w.tick();
      expect(reads(h, 'h10'), 3);
    });

    test('checks appearing after one empty read notify', () async {
      final h = _harness();
      h.forge.checksBySha['h10'] = _none;
      final w = h.watcher;
      await h.settle();
      await w.tick();

      h.forge.checksBySha['h10'] = _success;
      await w.tick();

      expect(h.bodies, ['CI passed on topic-10 (PR #10)']);
    });
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
      1,
      reason: 'losing focus only seeds the repo that has no snapshot yet',
    );
    expect(h.notifier.shown, isEmpty);

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

    h.now = h.now.add(const Duration(minutes: 30));
    await w.tick();
    expect(
      h.forge.pullRequestsCalls,
      0,
      reason: 'the pause must last until the reported reset',
    );

    h.now = h.now.add(const Duration(minutes: 30, seconds: 1));
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

  test('a repo with only requests on never asks about CI', () async {
    final h = _harness(ci: false);
    final w = h.watcher;
    await h.settle();

    await w.tick();
    h.prs.add(_pr(11));
    await w.tick();

    expect(h.forge.checkedRefs, isEmpty);
    expect(h.bodies, ['PR #11 opened: Change 11']);
  });

  test('a repo with only CI on never looks up a vanished request', () async {
    final h = _harness(
      pullRequests: false,
      details: {
        10: PullRequestDetail(request: _pr(10, state: PullRequestState.merged)),
      },
    );
    final w = h.watcher;
    await h.settle();

    await w.tick();
    h.prs.clear();
    await w.tick();

    expect(h.forge.pullRequestCalls, 0);
    expect(h.notifier.shown, isEmpty);
  });

  test('CI turned back on records what finished meanwhile silently', () async {
    final h = _harness(ci: false);
    final w = h.watcher;
    await h.settle();
    await w.tick();

    h.forge.checksBySha['u1'] = _success;
    h.c.read(settingsProvider.notifier).setNotify(NotifyEvent.ci, true);
    await h.settle();
    await w.tick();
    expect(h.notifier.shown, isEmpty);

    h.forge.checksBySha['h10'] = _success;
    await w.tick();
    expect(h.bodies, ['CI passed on topic-10 (PR #10)']);
  });

  test('no tab to watch leaves the timer unarmed', () async {
    final h = _harness(tabs: const []);
    final w = h.watcher;
    await h.settle();
    expect(w.scheduledInterval, isNull);
  });

  test('a tab with notifications off leaves the timer unarmed', () async {
    final h = _harness(ci: false, pullRequests: false);
    final w = h.watcher;
    await h.settle();
    expect(w.scheduledInterval, isNull);
  });

  test('an upstream on a remote other than the forge is not read', () async {
    final h = _harness(upstreamRemote: 'fork');
    final w = h.watcher;
    await h.settle();

    await w.tick();

    expect(h.forge.checkedRefs, ['h10']);
  });

  test('one commit whose CI cannot be read does not stall the repo', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();
    await w.tick();

    h.forge.checksErrorsBySha['h10'] = const ForgeServerFault(422);
    h.forge.checksBySha['h11'] = _success;
    h.forge.checksBySha['u1'] = _success;
    h.prs.add(_pr(11));
    await w.tick();

    expect(
      h.bodies,
      unorderedEquals([
        'PR #11 opened: Change 11',
        'CI passed on topic-11 (PR #11)',
        'CI passed on feature',
      ]),
    );
    expect(w.scheduledInterval, const Duration(seconds: 120));
    expect(w.snapshots[_path]!.openPrs.keys, unorderedEquals([10, 11]));
  });

  test('a rate-limited CI read still backs the watcher off', () async {
    final h = _harness();
    final w = h.watcher;
    await h.settle();
    await w.tick();

    h.forge.checksErrorsBySha['h10'] = const ForgeRateLimited(null);
    await w.tick();

    expect(w.scheduledInterval, const Duration(seconds: 240));
  });

  for (final refused in <ForgeError>[
    const ForgeRateLimited(null),
    ForgeUnauthenticated(),
  ]) {
    test('a gone request whose lookup is refused (${refused.runtimeType}) '
        'waits for a later tick', () async {
      final h = _harness(
        prs: [_pr(10), _pr(11)],
        details: {
          10: PullRequestDetail(
            request: _pr(10, state: PullRequestState.merged),
          ),
        },
      );
      final w = h.watcher;
      await h.settle();
      await w.tick();

      h.prs.removeWhere((p) => p.number == 10);
      h.forge.pullRequestError = refused;
      await w.tick();

      expect(h.notifier.shown, isEmpty);
      expect(w.scheduledInterval, const Duration(seconds: 240));
      expect(w.snapshots[_path]!.openPrs.keys, contains(10));

      h.forge.pullRequestError = null;
      await w.tick();

      expect(h.bodies, ['PR #10 merged']);
    });
  }

  test('a host that cannot be resolved does not skip the others', () async {
    const other = ForgeHost(
      kind: ForgeKind.github,
      host: 'ghe.corp',
      owner: 'o',
      repo: 'r',
    );
    final h = _harness(
      tabs: const ['/a', '/b'],
      hostFor: (path) async =>
          path == '/a' ? throw StateError('no remote') : other,
    );
    final w = h.watcher;
    await h.settle();

    await w.tick();

    expect(h.forge.pullRequestsCalls, 1);
    expect(w.snapshots.keys, ['/b']);
  });

  test('a budget that cannot be read does not skip other hosts', () async {
    const other = ForgeHost(
      kind: ForgeKind.github,
      host: 'ghe.corp',
      owner: 'o',
      repo: 'r',
    );
    final h = _harness(
      tabs: const ['/a', '/b'],
      hostFor: (path) async => path == '/a' ? _host : other,
      limitFor: (path) async =>
          path == '/a' ? throw StateError('budget') : null,
    );
    final w = h.watcher;
    await h.settle();

    await w.tick();

    expect(h.forge.pullRequestsCalls, 1);
    expect(w.snapshots.keys, ['/b']);
  });

  group('routing to the gate', () {
    test('a single request event goes through pull requests', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();
      h.prs.add(_pr(11));
      await w.tick();
      expect(h.kinds, [NotifyEvent.pullRequests]);
    });

    test('a single CI event goes through CI', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();
      h.forge.checksBySha['u1'] = _success;
      await w.tick();
      expect(h.kinds, [NotifyEvent.ci]);
    });

    test('a mixed batch goes through pull requests once', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();
      h.forge.checksBySha['h10'] = _success;
      h.forge.checksBySha['u1'] = _success;
      h.prs.addAll([_pr(11), _pr(12)]);
      await w.tick();
      expect(h.kinds, [NotifyEvent.pullRequests]);
      expect(h.notifier.shown, hasLength(1));
    });
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
      final interval = w.scheduledInterval!;

      // An early tick (a timer is never this early, but a pause measured in
      // ticks rather than time would let it through) still waits.
      h.now = h.now.add(interval ~/ 2);
      await w.tick();
      expect(h.forge.pullRequestsCalls, 0);

      h.now = h.now.add(interval ~/ 2);
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
      final h = _harness(
        ci: false,
        details: {
          10: PullRequestDetail(
            request: _pr(10, state: PullRequestState.merged),
          ),
        },
      );
      final w = h.watcher;
      await h.settle();
      await w.tick();
      expect(w.snapshots.keys, [_path]);

      // Toggled in Preferences, so the window has focus and no tick runs
      // while the setting is off.
      final settings = h.c.read(settingsProvider.notifier);
      settings.setNotify(NotifyEvent.pullRequests, false);
      await h.settle();
      expect(w.snapshots, isEmpty);

      h.prs
        ..clear()
        ..add(_pr(12));
      settings.setNotify(NotifyEvent.pullRequests, true);
      await h.settle();
      await w.tick();

      expect(h.notifier.shown, isEmpty);
      expect(h.forge.pullRequestCalls, 0);
      expect(w.snapshots[_path]!.openPrs.keys, [12]);
    });

    test('CI turned off and on with no tick between stays silent', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();

      final settings = h.c.read(settingsProvider.notifier);
      settings.setNotify(NotifyEvent.ci, false);
      await h.settle();
      h.forge.checksBySha['u1'] = _success;
      settings.setNotify(NotifyEvent.ci, true);
      await h.settle();
      await w.tick();

      expect(h.notifier.shown, isEmpty);
    });

    test('a closed and reopened tab re-seeds silently', () async {
      final h = _harness(
        details: {
          10: PullRequestDetail(
            request: _pr(10, state: PullRequestState.merged),
          ),
        },
      );
      final w = h.watcher;
      await h.settle();
      await w.tick();

      final ws = h.c.read(workspaceProvider.notifier);
      ws.closeTab(1);
      await h.settle();
      expect(w.snapshots, isEmpty);

      h.prs
        ..clear()
        ..add(_pr(12));
      ws.openRepo(_path);
      await h.settle();
      await w.tick();

      expect(h.notifier.shown, isEmpty);
      expect(h.forge.pullRequestCalls, 0);
    });
  });

  test(
    'a repo dropped while its request list is read stores nothing',
    () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      final held = Completer<void>();
      h.forge.pullRequestsHold = held.future;

      final run = w.tick();
      await h.settle();
      expect(h.forge.pullRequestsCalls, 1);

      final settings = h.c.read(settingsProvider.notifier);
      settings.setNotify(NotifyEvent.pullRequests, false);
      settings.setNotify(NotifyEvent.ci, false);
      await h.settle();
      held.complete();
      await run;

      expect(w.snapshots, isEmpty);
    },
  );

  group('focus stretches', () {
    test('focus held past one interval re-seeds as soon as it ends', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();

      final focus = h.c.read(windowFocusedProvider.notifier);
      focus.state = true;
      await h.settle();
      h.now = h.now.add(const Duration(seconds: 121));
      h.prs.add(_pr(11));
      focus.state = false;
      await h.settle();
      expect(h.forge.pullRequestsCalls, 2, reason: 'seeded on blur');
      expect(h.notifier.shown, isEmpty);

      // Opened before the first tick after blur: still news.
      h.prs.add(_pr(12));
      await w.tick();
      expect(h.bodies, ['PR #12 opened: Change 12']);
    });

    test(
      'CI finishing before the first tick after a long focus notifies',
      () async {
        final h = _harness();
        final w = h.watcher;
        await h.settle();
        await w.tick();

        final focus = h.c.read(windowFocusedProvider.notifier);
        focus.state = true;
        await h.settle();
        h.now = h.now.add(const Duration(seconds: 121));
        focus.state = false;
        await h.settle();
        expect(h.notifier.shown, isEmpty);

        h.forge.checksBySha['u1'] = _success;
        await w.tick();
        expect(h.bodies, ['CI passed on feature']);
      },
    );

    test('the first blur after launch seeds at once', () async {
      final h = _harness(focused: true);
      final w = h.watcher;
      await h.settle();
      expect(h.forge.pullRequestsCalls, 0);

      h.c.read(windowFocusedProvider.notifier).state = false;
      await h.settle();
      expect(h.forge.pullRequestsCalls, 1);
      expect(w.snapshots.keys, [_path]);
      expect(h.notifier.shown, isEmpty);

      h.prs.add(_pr(11));
      await w.tick();
      expect(h.bodies, ['PR #11 opened: Change 11']);
    });

    test('a failed seed on blur leaves the backoff alone', () async {
      final h = _harness(focused: true);
      final w = h.watcher;
      await h.settle();

      h.forge.pullRequestsError = const ForgeUnauthenticated();
      h.c.read(windowFocusedProvider.notifier).state = false;
      await h.settle();
      expect(h.forge.pullRequestsCalls, 1);
      expect(w.snapshots, isEmpty);
      expect(w.scheduledInterval, const Duration(seconds: 120));

      await w.tick();
      expect(
        w.scheduledInterval,
        const Duration(seconds: 240),
        reason: 'one failure: the tick, not the seed before it',
      );

      h.forge.pullRequestsError = null;
      h.prs.add(_pr(11));
      await w.tick();
      expect(h.notifier.shown, isEmpty, reason: 'the tick seeds instead');
      expect(w.snapshots.keys, [_path]);
    });

    test(
      'a repo whose seed keeps failing is retried once an interval',
      () async {
        final h = _harness(focused: true);
        h.watcher;
        await h.settle();
        h.forge.pullRequestsError = const ForgeUnauthenticated();
        final focus = h.c.read(windowFocusedProvider.notifier);

        focus.state = false;
        await h.settle();
        expect(h.forge.pullRequestsCalls, 1);

        for (var i = 0; i < 3; i++) {
          focus.state = true;
          await h.settle();
          h.now = h.now.add(const Duration(seconds: 10));
          focus.state = false;
          await h.settle();
        }
        expect(h.forge.pullRequestsCalls, 1, reason: 'glances cost no read');

        focus.state = true;
        await h.settle();
        h.now = h.now.add(const Duration(seconds: 100));
        focus.state = false;
        await h.settle();
        expect(h.forge.pullRequestsCalls, 2, reason: 'an interval has passed');
      },
    );

    test('a watcher created unfocused waits for its timer', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();

      expect(h.forge.pullRequestsCalls, 0);
      expect(w.scheduledInterval, const Duration(seconds: 120));
    });

    test('a tick asked for during a seed runs after it', () async {
      var held = Completer<ForgeRateLimit?>();
      final h = _harness(limitFor: (_) => held.future);
      final w = h.watcher;
      await h.settle();

      // A first tick fails, so the repo has no snapshot for the seed.
      h.forge.pullRequestsError = const ForgeUnauthenticated();
      final first = w.tick();
      await h.settle();
      final focus = h.c.read(windowFocusedProvider.notifier);
      focus.state = true;
      await h.settle();
      focus.state = false;
      await h.settle();

      final tickBudget = held;
      held = Completer<ForgeRateLimit?>();
      final seedBudget = held;
      tickBudget.complete(null);
      await first;
      await h.settle();
      expect(h.forge.pullRequestsCalls, 1, reason: 'the seed is held');
      final budgetReads = h.reads['budget'];

      h.forge.pullRequestsError = null;
      final second = w.tick();
      await h.settle();
      expect(
        h.reads['budget'],
        budgetReads,
        reason: 'no tick alongside the seed',
      );

      held = Completer<ForgeRateLimit?>()..complete(null);
      seedBudget.complete(null);
      await second;

      expect(h.forge.pullRequestsCalls, 3, reason: 'tick, seed, then tick');
      expect(w.snapshots.keys, [_path]);
    });

    test('a short glance costs no read on blur', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();

      final focus = h.c.read(windowFocusedProvider.notifier);
      focus.state = true;
      await h.settle();
      h.now = h.now.add(const Duration(seconds: 60));
      focus.state = false;
      await h.settle();

      expect(h.forge.pullRequestsCalls, 1);
    });

    test('a blur with the master switch off reads nothing', () async {
      final h = _harness(master: false, focused: true);
      h.watcher;
      await h.settle();

      h.c.read(windowFocusedProvider.notifier).state = false;
      await h.settle();

      expect(h.reads, isEmpty);
      expect(h.forge.pullRequestsCalls, 0);
    });

    test('a blur with nothing eligible reads nothing', () async {
      final h = _harness(ci: false, pullRequests: false, focused: true);
      h.watcher;
      await h.settle();

      h.c.read(windowFocusedProvider.notifier).state = false;
      await h.settle();

      expect(h.forge.pullRequestsCalls, 0);
    });

    test(
      'a blur during a tick waits for it instead of reading alongside',
      () async {
        var held = Completer<ForgeRateLimit?>();
        final h = _harness(limitFor: (_) => held.future);
        final w = h.watcher;
        await h.settle();

        final first = w.tick();
        await h.settle();
        final budgetReads = h.reads['budget'];
        expect(budgetReads, isNotNull);

        final focus = h.c.read(windowFocusedProvider.notifier);
        focus.state = true;
        await h.settle();
        h.now = h.now.add(const Duration(seconds: 121));
        focus.state = false;
        await h.settle();
        expect(
          h.reads['budget'],
          budgetReads,
          reason: 'no seed while the tick runs',
        );

        held.complete(null);
        held = Completer<ForgeRateLimit?>()..complete(null);
        await first;
        await h.settle();

        expect(h.forge.pullRequestsCalls, 1);
        expect(w.snapshots.keys, [_path]);
        expect(w.scheduledInterval, const Duration(seconds: 120));
      },
    );

    test('a short focus keeps what was seen before it', () async {
      final h = _harness();
      final w = h.watcher;
      await h.settle();
      await w.tick();

      final focus = h.c.read(windowFocusedProvider.notifier);
      focus.state = true;
      await h.settle();
      h.now = h.now.add(const Duration(seconds: 60));
      h.prs.add(_pr(11));
      focus.state = false;
      await h.settle();
      await w.tick();

      expect(h.bodies, ['PR #11 opened: Change 11']);
    });
  });

  test('with the master switch off nothing is read or armed', () async {
    final h = _harness(master: false);
    final w = h.watcher;
    await h.settle();
    expect(w.scheduledInterval, isNull);

    await w.tick();
    await h.settle();

    expect(h.reads, isEmpty);
    expect(h.kv.gets, 0);
    expect(h.forge.pullRequestsCalls, 0);
    expect(w.scheduledInterval, isNull);
  });

  test('a rate-limited repo skips the rest of its host this tick', () async {
    final h = _harness(tabs: const ['/a', '/b']);
    final w = h.watcher;
    await h.settle();

    h.forge.pullRequestsError = const ForgeRateLimited(null);
    await w.tick();

    expect(h.forge.pullRequestsCalls, 1);
    expect(w.scheduledInterval, const Duration(seconds: 240));
  });
}
