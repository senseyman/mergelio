import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge_refresh.dart';
import 'package:mergelio/state/notification_prefs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/notifications_tab.dart';
import 'package:mergelio/ui/preferences/repo_config_tab.dart';
import 'package:mergelio/ui/preferences/repo_notifications_section.dart';

/// Answers the config read with nothing and refuses anything else.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(1, '', '');
  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

late ProviderContainer _c;
late InMemoryKeyValueStore _kv;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppSettings settings = const AppSettings(),
  Future<bool> Function()? eligible,
  double width = 520,
  Locale? locale,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _kv = InMemoryKeyValueStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        kvStoreProvider.overrideWithValue(_kv),
        settingsProvider.overrideWith(
          (ref) => SettingsController(InMemorySettingsRepository(), settings),
        ),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            const ProfilesState(profiles: []),
          ),
        ),
        forgeRefreshEligibleProvider.overrideWith(
          (ref, path) => (eligible ?? () async => true)(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              _c = ProviderScope.containerOf(context);
              return child;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _switch(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(Switch),
);

bool? _onChangedIsNull(WidgetTester tester, String key) =>
    tester.widget<Switch>(_switch(key)).onChanged == null;

Future<void> _pick(WidgetTester tester, String key, String text) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  group('NotificationsTab', () {
    testWidgets(
      'event switches and threshold are disabled while master is off',
      (tester) async {
        await _pump(tester, const NotificationsTab());
        expect(_onChangedIsNull(tester, 'ntf-master'), isFalse);
        for (final k in ['ntf-longOps', 'ntf-ci', 'ntf-pullRequests']) {
          expect(_onChangedIsNull(tester, k), isTrue, reason: k);
        }
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('ntf-secs')),
              )
              .onChanged,
          isNull,
        );
      },
    );

    testWidgets('master switch persists and unlocks the event switches', (
      tester,
    ) async {
      await _pump(tester, const NotificationsTab());
      await tester.tap(_switch('ntf-master'));
      await tester.pumpAndSettle();
      expect(_c.read(settingsProvider).notificationsEnabled, isTrue);
      expect(_onChangedIsNull(tester, 'ntf-ci'), isFalse);
      await tester.tap(_switch('ntf-ci'));
      await tester.pumpAndSettle();
      expect(_c.read(settingsProvider).notifyCi, isTrue);
      expect(_c.read(settingsProvider).notifyLongOps, isFalse);
    });

    testWidgets('threshold is enabled only with master and long ops on', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationsTab(),
        settings: const AppSettings(notificationsEnabled: true),
      );
      DropdownButton<int> dd() =>
          tester.widget(find.byKey(const ValueKey('ntf-secs')));
      expect(dd().onChanged, isNull);
      await tester.tap(_switch('ntf-longOps'));
      await tester.pumpAndSettle();
      expect(dd().onChanged, isNotNull);
      await _pick(tester, 'ntf-secs', '60 s');
      expect(_c.read(settingsProvider).notifyLongOpSeconds, 60);
    });

    testWidgets('a stored threshold outside the choices is still shown', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationsTab(),
        settings: const AppSettings(
          notificationsEnabled: true,
          notifyLongOps: true,
          notifyLongOpSeconds: 45,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('45 s'), findsOneWidget);
    });

    testWidgets('help text is shown and no width overflows', (tester) async {
      for (final w in [520.0, 440.0, 336.0]) {
        await _pump(tester, const NotificationsTab(), width: w);
        expect(find.textContaining('GitHub/GitLab'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
    });

    testWidgets('renders in Ukrainian', (tester) async {
      await _pump(tester, const NotificationsTab(), locale: const Locale('uk'));
      expect(find.text('Сповіщення на робочому столі'), findsOneWidget);
    });
  });

  group('RepoNotificationsSection', () {
    const repo = '/repo';

    testWidgets('use-global label names the current global value', (
      tester,
    ) async {
      await _pump(
        tester,
        const RepoNotificationsSection(repoPath: repo),
        settings: const AppSettings(notificationsEnabled: true, notifyCi: true),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ntf-repo-ci')),
          matching: find.text('Use global (On)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ntf-repo-longOps')),
          matching: find.text('Use global (Off)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('choosing an override saves it', (tester) async {
      await _pump(
        tester,
        const RepoNotificationsSection(repoPath: repo),
        settings: const AppSettings(notificationsEnabled: true),
      );
      await _pick(tester, 'ntf-repo-ci', 'Off');
      final p = _c.read(repoNotifyPrefsProvider(repo));
      expect(p.of(NotifyEvent.ci), NotifyOverride.off);
      expect(p.of(NotifyEvent.longOps), NotifyOverride.inherit);
      await _c.read(repoNotifyPrefsProvider(repo).notifier).loaded;
      expect(await _kv.get('notifications:$repo'), contains('"ci":"off"'));
    });

    testWidgets('rows stay editable with master off, under one hint', (
      tester,
    ) async {
      await _pump(tester, const RepoNotificationsSection(repoPath: repo));
      expect(find.textContaining('turned on'), findsOneWidget);
      await _pick(tester, 'ntf-repo-longOps', 'On');
      expect(
        _c.read(repoNotifyPrefsProvider(repo)).of(NotifyEvent.longOps),
        NotifyOverride.on,
      );
    });

    testWidgets('no hint when master is on', (tester) async {
      await _pump(
        tester,
        const RepoNotificationsSection(repoPath: repo),
        settings: const AppSettings(notificationsEnabled: true),
      );
      expect(find.textContaining('turned on'), findsNothing);
    });

    for (final (name, eligible, shown)
        in <(String, Future<bool> Function(), bool)>[
          (
            'false shows the no-forge hint on CI and PR rows',
            () async => false,
            true,
          ),
          ('true shows no hint', () async => true, false),
          (
            'an error shows no hint',
            () async => throw StateError('boom'),
            false,
          ),
          (
            'still loading shows no hint',
            () => Completer<bool>().future,
            false,
          ),
        ]) {
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          const RepoNotificationsSection(repoPath: repo),
          eligible: eligible,
        );
        expect(
          find.textContaining('No forge account'),
          shown ? findsNWidgets(2) : findsNothing,
        );
      });
    }

    testWidgets('lays out at every dialog width', (tester) async {
      for (final w in [520.0, 440.0, 336.0]) {
        await _pump(
          tester,
          const RepoNotificationsSection(repoPath: repo),
          eligible: () async => false,
          width: w,
        );
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
    });

    testWidgets('RepoConfigTab appends the section when a repo is open', (
      tester,
    ) async {
      await _pump(tester, const RepoConfigTab(repoPath: repo));
      await tester.scrollUntilVisible(
        find.text('Notifications for this repository'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Notifications for this repository'), findsOneWidget);
    });
  });
}
