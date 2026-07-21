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

    test('default auto-fetch interval is 5 seconds', () {
      expect(const AppSettings().autoFetchIntervalSeconds, 5);
    });

    test('setAutoFetchInterval clamps to a 5s floor', () {
      final c = live(const AppSettings());
      addTearDown(c.dispose);
      final s = c.read(settingsProvider.notifier);
      s.setAutoFetchInterval(1);
      expect(c.read(settingsProvider).autoFetchIntervalSeconds, 5);
      s.setAutoFetchInterval(30);
      expect(c.read(settingsProvider).autoFetchIntervalSeconds, 30);
    });

    test('scheduler uses the settings interval and reschedules on change', () {
      final c = live(
        const AppSettings(autoFetch: true, autoFetchIntervalSeconds: 5),
      );
      addTearDown(c.dispose);
      final af = c.read(autoFetchProvider);
      expect(af.scheduledInterval, const Duration(seconds: 5));

      c.read(settingsProvider.notifier).setAutoFetchInterval(30);
      expect(af.scheduledInterval, const Duration(seconds: 30));
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
}
