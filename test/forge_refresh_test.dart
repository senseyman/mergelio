// The pull-request panel's automatic refresh: gated on a token, the window
// having focus and an active repository at once, backed off on failure the
// same way auto-fetch is, and reset by anything else that already refreshed.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/models.dart' show Issue;
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/window_focus.dart';
import 'package:mergelio/state/workspace.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);
const _path = '/repo';

/// The overrides a settled container needs, split out from [_container] so a
/// test can hand the identical list back to [ProviderContainer.updateOverrides]
/// with just one entry changed — Riverpod only updates existing overrides in
/// place, it cannot add or remove any, so the list length and order must
/// match what the container was built with.
List<Override> _overrides({
  AppSettings settings = const AppSettings(),
  ForgeHost? host = _host,
  ForgeToken? token = const ForgeToken('ghp_x'),
  bool focused = true,
  bool openRepo = true,
  ForgePanel Function(String path)? panel,
  List<Issue> Function(String path)? issues,
}) {
  final workspace = WorkspaceController();
  if (openRepo) workspace.openRepo(_path);
  return [
    settingsProvider.overrideWith(
      (ref) => SettingsController(InMemorySettingsRepository(), settings),
    ),
    workspaceProvider.overrideWith((ref) => workspace),
    windowFocusedProvider.overrideWith((ref) => focused),
    forgeHostProvider.overrideWith((ref, path) async => host),
    forgeTokenProvider.overrideWith((ref, path) async => token),
    pullRequestPanelProvider.overrideWith(
      (ref, path) async => panel?.call(path) ?? const ForgePanel(),
    ),
    issuePanelProvider.overrideWith(
      (ref, path) async => issues?.call(path) ?? const [],
    ),
  ];
}

/// A settled container with a repo open at [_path], ready to be nudged into
/// whichever host/token combination a test needs.
ProviderContainer _container({
  AppSettings settings = const AppSettings(),
  ForgeHost? host = _host,
  ForgeToken? token = const ForgeToken('ghp_x'),
  bool focused = true,
  bool openRepo = true,
  ForgePanel Function(String path)? panel,
  List<Issue> Function(String path)? issues,
}) => ProviderContainer(
  overrides: _overrides(
    settings: settings,
    host: host,
    token: token,
    focused: focused,
    openRepo: openRepo,
    panel: panel,
    issues: issues,
  ),
);

/// Flushes the microtasks a family FutureProvider chain needs to settle
/// after a container is built or an override changes.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('a panel that settles on an error backs the next tick off', () async {
    // The scheduler learns a tick failed by the reload throwing, not by a
    // false return. A rate-limited forge must not be retried at full rate
    // every interval, so this pins the path a reviewer suspected was silent.
    final c = _container(panel: (path) => throw const ForgeRateLimited(null));
    addTearDown(c.dispose);
    final ctl = c.read(forgeRefreshProvider);
    await _settle();
    final before = ctl.scheduledInterval;

    await ctl.tick();
    await _settle();

    expect(
      ctl.scheduledInterval,
      isNot(before),
      reason:
          'a failed refresh left the interval where it was, so a '
          'rate-limited forge would be hit again at full rate',
    );
    expect(ctl.scheduledInterval!, greaterThan(before!));
  });

  group('eligibility gates the timer', () {
    test('no timer without a token', () async {
      final c = _container(token: null);
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();

      expect(ctl.scheduledInterval, isNull);
    });

    test('no timer without a forge host', () async {
      final c = _container(host: null, token: null);
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();

      expect(ctl.scheduledInterval, isNull);
    });

    test('no timer with no repository open', () async {
      final c = _container(openRepo: false);
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();

      expect(ctl.scheduledInterval, isNull);
    });

    test('a timer starts once a token and host both resolve', () async {
      final c = _container(
        settings: const AppSettings(forgeRefreshIntervalSeconds: 300),
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();

      expect(ctl.scheduledInterval, const Duration(seconds: 300));
    });

    test('losing the token cancels the timer', () async {
      // updateOverrides cannot change what an already-created family member
      // resolves to — a family override it is handed only ever applies to
      // members mounted after the swap, and forgeTokenProvider(_path) is
      // mounted the moment the controller settles below. So the override
      // closure captures a mutable cell instead: invalidating the provider
      // re-runs the very same closure, which by then reads the token as
      // gone.
      final workspace = WorkspaceController()..openRepo(_path);
      ForgeToken? token = const ForgeToken('ghp_x');
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          workspaceProvider.overrideWith((ref) => workspace),
          windowFocusedProvider.overrideWith((ref) => true),
          forgeHostProvider.overrideWith((ref, path) async => _host),
          forgeTokenProvider.overrideWith((ref, path) async => token),
          pullRequestPanelProvider.overrideWith(
            (ref, path) async => const ForgePanel(),
          ),
          issuePanelProvider.overrideWith((ref, path) async => const []),
        ],
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();
      expect(ctl.scheduledInterval, isNotNull);

      token = null;
      c.invalidate(forgeTokenProvider(_path));
      await _settle();

      expect(ctl.scheduledInterval, isNull);
    });
  });

  group('interval from settings', () {
    test('default forge-refresh interval is 10 minutes', () {
      expect(const AppSettings().forgeRefreshIntervalSeconds, 600);
    });

    test('setForgeRefreshInterval clamps to a 120s floor', () {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final s = c.read(settingsProvider.notifier);
      s.setForgeRefreshInterval(5);
      expect(c.read(settingsProvider).forgeRefreshIntervalSeconds, 120);
      s.setForgeRefreshInterval(900);
      expect(c.read(settingsProvider).forgeRefreshIntervalSeconds, 900);
    });

    test('a stored sub-minimum interval is migrated up to the floor', () {
      expect(
        migrateSettings(const AppSettings(forgeRefreshIntervalSeconds: 5))
            .forgeRefreshIntervalSeconds,
        120,
      );
      expect(
        migrateSettings(const AppSettings(forgeRefreshIntervalSeconds: 900))
            .forgeRefreshIntervalSeconds,
        900,
      );
    });

    test('changing the interval setting reschedules a running timer', () async {
      final c = _container(
        settings: const AppSettings(forgeRefreshIntervalSeconds: 300),
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();
      expect(ctl.scheduledInterval, const Duration(seconds: 300));

      c.read(settingsProvider.notifier).setForgeRefreshInterval(150);
      expect(ctl.scheduledInterval, const Duration(seconds: 150));
    });
  });

  group('window focus', () {
    test('tick skips the refresh while the window is unfocused', () async {
      var calls = 0;
      final c = _container(
        focused: false,
        panel: (path) {
          calls++;
          return const ForgePanel();
        },
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();
      final interval = ctl.scheduledInterval;

      await ctl.tick();

      expect(calls, 0);
      // A skip is not a failure: the timer stays on the same interval.
      expect(ctl.scheduledInterval, interval);
    });

    test('regaining focus after a skipped tick refreshes at once', () async {
      var calls = 0;
      final c = _container(
        focused: false,
        panel: (path) {
          calls++;
          return const ForgePanel();
        },
      );
      addTearDown(c.dispose);
      // Building the panel provider once up front, same as the invalidation
      // test below, so the tick's own invalidate does not also cover the
      // provider's very first (debug-only double) build.
      final sub = c.listen(pullRequestPanelProvider(_path), (_, _) {});
      addTearDown(sub.close);
      await c.read(pullRequestPanelProvider(_path).future);
      calls = 0;

      final ctl = c.read(forgeRefreshProvider);
      await _settle();

      await ctl.tick();
      expect(calls, 0);

      c.read(windowFocusedProvider.notifier).state = true;
      await ctl.inFlightTick;

      expect(calls, 1);
    });
  });

  group('failure backoff', () {
    test(
      'a failing tick backs the interval off; a success resets it',
      () async {
        var fail = true;
        final c = _container(
          settings: const AppSettings(forgeRefreshIntervalSeconds: 120),
          panel: (path) {
            if (fail) throw Exception('rate limited');
            return const ForgePanel();
          },
        );
        addTearDown(c.dispose);
        final ctl = c.read(forgeRefreshProvider);
        await _settle();
        expect(ctl.scheduledInterval, const Duration(seconds: 120));

        await ctl.tick();
        expect(ctl.scheduledInterval, const Duration(seconds: 240));
        await ctl.tick();
        expect(ctl.scheduledInterval, const Duration(seconds: 480));

        fail = false;
        await ctl.tick();
        expect(ctl.scheduledInterval, const Duration(seconds: 120));
      },
    );
  });

  group('a tick error does not escape', () {
    test('an exception refreshing the panel counts as a failure, not an '
        'unhandled error', () async {
      // tick() runs unawaited from a Timer callback in production; an
      // exception this raw would surface as an unhandled async error
      // instead of the ordinary backoff a failed refresh earns.
      final c = _container(
        settings: const AppSettings(forgeRefreshIntervalSeconds: 120),
        panel: (path) => throw StateError('boom'),
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();
      expect(ctl.scheduledInterval, const Duration(seconds: 120));

      // Must complete normally: a tick that let this escape would take
      // the scheduler down with it and end forge-refresh for the rest of
      // the session.
      await ctl.tick();

      expect(ctl.scheduledInterval, const Duration(seconds: 240));
    });
  });

  group('any refresh resets the timer', () {
    test(
      'refreshNow re-arms the tracked repository at the base interval',
      () async {
        var fail = true;
        final c = _container(
          settings: const AppSettings(forgeRefreshIntervalSeconds: 120),
          panel: (path) {
            if (fail) throw Exception('offline');
            return const ForgePanel();
          },
        );
        addTearDown(c.dispose);
        final ctl = c.read(forgeRefreshProvider);
        await _settle();

        await ctl.tick();
        expect(ctl.scheduledInterval, const Duration(seconds: 240));

        fail = false;
        ctl.refreshNow(_path);

        expect(ctl.scheduledInterval, const Duration(seconds: 120));
      },
    );

    test('refreshNow invalidates the panel it is given', () async {
      var calls = 0;
      final c = _container(
        panel: (path) {
          calls++;
          return const ForgePanel();
        },
      );
      addTearDown(c.dispose);
      c.read(forgeRefreshProvider);
      await _settle();
      // Establish a listener so the invalidation is observable synchronously.
      final sub = c.listen(pullRequestPanelProvider(_path), (_, _) {});
      addTearDown(sub.close);
      await c.read(pullRequestPanelProvider(_path).future);
      final before = calls;

      c.read(forgeRefreshProvider).refreshAfterGitOp(_path);
      await c.read(pullRequestPanelProvider(_path).future);

      expect(calls, greaterThan(before));
    });

    test('refreshNow for a repository the scheduler is not tracking leaves '
        'the tracked timer untouched', () async {
      final c = _container(
        settings: const AppSettings(forgeRefreshIntervalSeconds: 120),
      );
      addTearDown(c.dispose);
      final ctl = c.read(forgeRefreshProvider);
      await _settle();
      final before = ctl.scheduledInterval;

      ctl.refreshNow('/some/other/repo');

      expect(ctl.scheduledInterval, before);
    });
  });

  test('refreshNow spends a refresh even with no token on file', () async {
    // The token gate belongs on paths that spend without being asked. A
    // person pressing refresh has asked, and a control that quietly does
    // nothing is worse than one that spends a request.
    var calls = 0;
    final c = _container(
      token: null,
      panel: (path) {
        calls++;
        return const ForgePanel();
      },
    );
    addTearDown(c.dispose);
    c.read(forgeRefreshProvider);
    await _settle();
    final sub = c.listen(pullRequestPanelProvider(_path), (_, _) {});
    addTearDown(sub.close);
    await c.read(pullRequestPanelProvider(_path).future);
    calls = 0;

    c.read(forgeRefreshProvider).refreshNow(_path);
    await _settle();

    expect(calls, 1);
  });

  test('a git op does not refetch a section nobody is watching', () async {
    var calls = 0;
    final c = _container(
      issues: (path) {
        calls++;
        return const <Issue>[];
      },
    );
    addTearDown(c.dispose);
    c.read(forgeRefreshProvider);
    await _settle();
    // The section was open once, so the panel holds a value...
    await c.read(issuePanelProvider(_path).future);
    expect(calls, 1);
    // ...and is collapsed now, so nothing is listening to it.

    c.read(forgeRefreshProvider).refreshAfterGitOp(_path);
    await _settle();

    expect(
      calls,
      1,
      reason:
          'invalidating leaves an unwatched panel dirty for whenever it is '
          'next shown. Forcing the reload here instead — with refresh, say '
          '— would make every fetch, pull and push pay for sections nobody '
          'can see',
    );
  });

  group('refreshAfterGitOp spends only what a token affords', () {
    test('leaves pull requests alone without a token on file', () async {
      var calls = 0;
      final c = _container(
        token: null,
        panel: (path) {
          calls++;
          return const ForgePanel();
        },
      );
      addTearDown(c.dispose);
      c.read(forgeRefreshProvider);
      await _settle();
      final sub = c.listen(pullRequestPanelProvider(_path), (_, _) {});
      addTearDown(sub.close);
      await c.read(pullRequestPanelProvider(_path).future);
      calls = 0;

      c.read(forgeRefreshProvider).refreshAfterGitOp(_path);
      await _settle();

      expect(
        calls,
        0,
        reason:
            'a fetch/pull/push run without a token must not spend the '
            'unauthenticated hourly budget on a panel refresh nobody asked '
            'for',
      );
    });

    test('still refreshes issues without a token on file', () async {
      var calls = 0;
      final c = _container(
        token: null,
        issues: (path) {
          calls++;
          return const <Issue>[];
        },
      );
      addTearDown(c.dispose);
      c.read(forgeRefreshProvider);
      await _settle();
      final sub = c.listen(issuePanelProvider(_path), (_, _) {});
      addTearDown(sub.close);
      await c.read(issuePanelProvider(_path).future);
      final before = calls;

      c.read(forgeRefreshProvider).refreshAfterGitOp(_path);
      await c.read(issuePanelProvider(_path).future);

      expect(
        calls,
        greaterThan(before),
        reason:
            'one issue request is noise beside the unauthenticated hourly '
            'budget, so a fetch, pull or push refreshes issues whether or '
            'not a token is connected',
      );
    });

    test('still refreshes the panel once a token is on file', () async {
      var calls = 0;
      final c = _container(
        panel: (path) {
          calls++;
          return const ForgePanel();
        },
      );
      addTearDown(c.dispose);
      c.read(forgeRefreshProvider);
      await _settle();
      final sub = c.listen(pullRequestPanelProvider(_path), (_, _) {});
      addTearDown(sub.close);
      await c.read(pullRequestPanelProvider(_path).future);
      final before = calls;

      c.read(forgeRefreshProvider).refreshAfterGitOp(_path);
      await c.read(pullRequestPanelProvider(_path).future);

      expect(calls, greaterThan(before));
    });
  });

  test('a tick that lands after disposal is inert', () async {
    final c = _container();
    final ctl = c.read(forgeRefreshProvider);
    await _settle();
    c.dispose();

    await ctl.tick();
    expect(ctl.scheduledInterval, isNull);
  });
}
