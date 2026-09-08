import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/auto_fetch.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/window_focus.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  late Directory origin;
  late Directory clone;
  const svc = SystemGitService();

  Future<void> g(Directory d, List<String> args) async {
    final r = await svc.run(args, repoPath: d.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(),
        ),
      ),
      autoFetchProvider.overrideWith(
        (ref) => AutoFetchController(ref, interval: const Duration(hours: 1)),
      ),
    ],
  );

  setUp(() async {
    origin = await Directory.systemTemp.createTemp('mergelio_af_origin_');
    await g(origin, ['init', '-q', '-b', 'main']);
    await g(origin, ['config', 'user.email', 't@e.com']);
    await g(origin, ['config', 'user.name', 'T']);
    await g(origin, ['config', 'commit.gpgsign', 'false']);
    await File('${origin.path}/a.txt').writeAsString('base\n');
    await g(origin, ['add', '.']);
    await g(origin, ['commit', '-q', '-m', 'base']);

    clone = await Directory.systemTemp.createTemp('mergelio_af_clone_');
    await svc.run(['clone', '-q', origin.path, clone.path]);
  });

  tearDown(() async {
    for (final d in [origin, clone]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  test('fetchNow pulls new origin commits into the active clone', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo(clone.path);
    final af = c.read(autoFetchProvider);

    await File('${origin.path}/b.txt').writeAsString('new\n');
    await g(origin, ['add', '.']);
    await g(origin, ['commit', '-q', '-m', 'second']);

    await af.fetchNow();

    final log = (await svc.run([
      'log',
      '--oneline',
      'origin/main',
    ], repoPath: clone.path)).out;
    expect(log, contains('second'));
  });

  test('fetchNow is a no-op on a repo with no remote', () async {
    final noRemote = await Directory.systemTemp.createTemp('mergelio_af_nr_');
    addTearDown(() => noRemote.delete(recursive: true));
    await g(noRemote, ['init', '-q', '-b', 'main']);

    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo(noRemote.path);
    final af = c.read(autoFetchProvider);

    // Must complete without throwing (no remote → skipped).
    await af.fetchNow();
  });

  test('auto-fetch tick shows no toast', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo(clone.path);
    final af = c.read(autoFetchProvider);

    await File('${origin.path}/b.txt').writeAsString('new\n');
    await g(origin, ['add', '.']);
    await g(origin, ['commit', '-q', '-m', 'second']);

    await af.fetchNow();

    expect(c.read(toastProvider), isEmpty);
  });

  test('manual fetch shows a toast', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo(clone.path);

    await c.read(repoActionsProvider(clone.path)).fetch();

    expect(c.read(toastProvider), isNotEmpty);
  });

  group('interval from settings', () {
    // A container whose auto-fetch controller reads the interval live from
    // settings (no interval override), so scheduling reflects the real path.
    ProviderContainer live(AppSettings initial) => ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(InMemorySettingsRepository(), initial),
        ),
      ],
    );

    test('default auto-fetch interval is 5 minutes', () {
      expect(const AppSettings().autoFetchIntervalSeconds, 300);
    });

    test('setAutoFetchInterval clamps to a 30s floor', () {
      final c = live(const AppSettings());
      addTearDown(c.dispose);
      final s = c.read(settingsProvider.notifier);
      s.setAutoFetchInterval(5);
      expect(c.read(settingsProvider).autoFetchIntervalSeconds, 30);
      s.setAutoFetchInterval(300);
      expect(c.read(settingsProvider).autoFetchIntervalSeconds, 300);
    });

    test('a stored sub-minimum interval is migrated up to the floor', () {
      expect(
        migrateSettings(
          const AppSettings(autoFetchIntervalSeconds: 5),
        ).autoFetchIntervalSeconds,
        30,
      );
      expect(
        migrateSettings(
          const AppSettings(autoFetchIntervalSeconds: 600),
        ).autoFetchIntervalSeconds,
        600,
      );
    });

    test('scheduler uses the settings interval and reschedules on change', () {
      final c = live(
        const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 300),
      );
      addTearDown(c.dispose);
      final af = c.read(autoFetchProvider);
      expect(af.scheduledInterval, const Duration(seconds: 300));

      c.read(settingsProvider.notifier).setAutoFetchInterval(60);
      expect(af.scheduledInterval, const Duration(seconds: 60));
    });

    test('scheduler floors a stored sub-minimum interval', () {
      final c = live(
        const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 5),
      );
      addTearDown(c.dispose);
      expect(c.read(autoFetchProvider).scheduledInterval, kMinAutoFetchDelay);
    });

    test('scheduler stops when auto-fetch is turned off', () {
      final c = live(const AppSettings(autoFetch: true));
      addTearDown(c.dispose);
      final af = c.read(autoFetchProvider);
      expect(af.scheduledInterval, isNotNull);

      c.read(settingsProvider.notifier).setAutoFetch(false);
      expect(af.scheduledInterval, isNull);
    });
  });

  group('failure backoff', () {
    test('delay doubles per consecutive failure, capped, never under base', () {
      const base = Duration(minutes: 5);
      expect(autoFetchDelay(base, 0), base);
      expect(autoFetchDelay(base, 1), const Duration(minutes: 10));
      expect(autoFetchDelay(base, 2), const Duration(minutes: 20));
      expect(autoFetchDelay(base, 3), kMaxAutoFetchDelay);
      expect(autoFetchDelay(base, 99), kMaxAutoFetchDelay);
      // A base longer than the cap wins: the user asked for that spacing.
      expect(
        autoFetchDelay(const Duration(hours: 2), 3),
        const Duration(hours: 2),
      );
    });

    test('a failing tick backs the timer off; a success resets it', () async {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 30),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      final af = c.read(autoFetchProvider);
      expect(af.scheduledInterval, const Duration(seconds: 30));

      await g(clone, ['remote', 'set-url', 'origin', '/nonexistent/mergelio']);
      await af.tick();
      expect(af.scheduledInterval, const Duration(seconds: 60));
      await af.tick();
      expect(af.scheduledInterval, const Duration(seconds: 120));

      await g(clone, ['remote', 'set-url', 'origin', origin.path]);
      await af.tick();
      expect(af.scheduledInterval, const Duration(seconds: 30));
    });
  });

  test('a tick that lands after disposal is inert', () async {
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(autoFetch: true),
          ),
        ),
      ],
    );
    c.read(workspaceProvider.notifier).openRepo(clone.path);
    final af = c.read(autoFetchProvider);
    c.dispose();

    // Must not read a disposed container, nor arm a timer nobody can cancel.
    await af.tick();
    expect(af.scheduledInterval, isNull);
  });

  test('a throwing tick counts as a failure and keeps the schedule', () async {
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 30),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openRepo(clone.path);
    final af = c.read(autoFetchProvider);

    // The repo directory going away mid-session makes `git remote` throw,
    // which must not take the scheduler down with it.
    await clone.delete(recursive: true);
    await af.tick();

    expect(af.scheduledInterval, const Duration(seconds: 60));
  });

  group('window focus', () {
    ProviderContainer focused(bool value) => ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 30),
          ),
        ),
        windowFocusedProvider.overrideWith((ref) => value),
      ],
    );

    Future<String> originLog() async => (await svc.run([
      'log',
      '--oneline',
      'origin/main',
    ], repoPath: clone.path)).out;

    Future<void> commitSecondOnOrigin() async {
      await File('${origin.path}/b.txt').writeAsString('new\n');
      await g(origin, ['add', '.']);
      await g(origin, ['commit', '-q', '-m', 'second']);
    }

    test('tick skips the fetch while the window is unfocused', () async {
      final c = focused(false);
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      await commitSecondOnOrigin();

      await c.read(autoFetchProvider).tick();

      expect(await originLog(), isNot(contains('second')));
      // A skip is not a failure: the timer stays on the base interval.
      expect(
        c.read(autoFetchProvider).scheduledInterval,
        const Duration(seconds: 30),
      );
    });

    test('regaining focus after a skipped tick fetches at once', () async {
      final c = focused(false);
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      final af = c.read(autoFetchProvider);
      await commitSecondOnOrigin();

      await af.tick();
      expect(await originLog(), isNot(contains('second')));

      c.read(windowFocusedProvider.notifier).state = true;
      await af.inFlightTick;

      expect(await originLog(), contains('second'));
      expect(af.scheduledInterval, const Duration(seconds: 30));
    });

    test('a focus flap with no skipped tick fetches nothing', () async {
      final c = focused(true);
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      final af = c.read(autoFetchProvider);
      await af.tick();

      await commitSecondOnOrigin();
      final focus = c.read(windowFocusedProvider.notifier);
      focus.state = false;
      focus.state = true;
      await af.inFlightTick;

      // Nothing was missed while away, so the timer is left to do its job.
      expect(await originLog(), isNot(contains('second')));
    });

    test('regaining focus while auto-fetch is off fetches nothing', () async {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(autoFetchIntervalSeconds: 30),
            ),
          ),
          windowFocusedProvider.overrideWith((ref) => false),
        ],
      );
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      final af = c.read(autoFetchProvider);
      await commitSecondOnOrigin();

      c.read(windowFocusedProvider.notifier).state = true;
      await af.inFlightTick;

      expect(await originLog(), isNot(contains('second')));
      expect(af.scheduledInterval, isNull);
    });

    test('tick fetches while the window is focused', () async {
      final c = focused(true);
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(clone.path);
      await commitSecondOnOrigin();

      await c.read(autoFetchProvider).tick();

      expect(await originLog(), contains('second'));
    });
  });
}
