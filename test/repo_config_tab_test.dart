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
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/preferences/preferences_dialog.dart';
import 'package:mergelio/ui/preferences/repo_config_tab.dart';

/// One record as `config --show-scope --show-origin -z` prints it.
String rec(String scope, String origin, String key, String value) =>
    '$scope\x00file:$origin\x00$key\n$value\x00';

/// Something no write path expects.
class _OddError implements Exception {}

/// Answers the config read with [config], records every other call, and
/// fails writes when [failWrites] is set.
class _FakeGit implements GitService {
  String config;
  bool failWrites;
  bool failRead;

  /// Throws something that is not a GitException on the next write.
  bool throwOddly = false;
  _FakeGit(this.config, {this.failWrites = false, this.failRead = false});

  final writes = <String>[];

  /// Holds every write until completed, to catch writes that overlap.
  Completer<void>? gate;
  int _running = 0;
  int maxRunning = 0;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.contains('--show-scope')) {
      if (failRead) return const GitResult(128, '', 'fatal: bad config line 3');
      return config.isEmpty
          ? const GitResult(1, '', '')
          : GitResult(0, config, '');
    }
    writes.add(args.join(' '));
    if (throwOddly) {
      throwOddly = false;
      throw _OddError();
    }
    _running++;
    if (_running > maxRunning) maxRunning = _running;
    await gate?.future;
    _running--;
    if (failWrites) {
      return const GitResult(255, '', 'error: could not lock config file');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _work = Profile(
  id: '1',
  label: 'Work',
  name: 'Maria K',
  email: 'maria@work.com',
  colorValue: 0xFF112233,
);

late ProviderContainer _container;

Future<_FakeGit> _pump(
  WidgetTester tester, {
  String config = '',
  String? repoPath = '/repo',
  Profile? profile,
  String pullStrategy = 'merge',
  bool failWrites = false,
  bool failRead = false,
  Locale? locale,
  double width = 560,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final git = _FakeGit(config, failWrites: failWrites, failRead: failRead);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(pullStrategy: pullStrategy),
          ),
        ),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            ProfilesState(profiles: [?profile], activeId: profile?.id),
          ),
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
              _container = ProviderScope.containerOf(context);
              return RepoConfigTab(repoPath: repoPath);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return git;
}

/// The chip [label] inside the row for [key].
Finder _chip(String key, String label) => find.descendant(
  of: find.byKey(ValueKey('rcfg-$key')),
  matching: find.widgetWithText(ChoiceChip, label),
);

bool _selected(WidgetTester tester, String key, String label) =>
    tester.widget<ChoiceChip>(_chip(key, label)).selected;

Finder _inRow(String key, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('rcfg-$key')), matching: f);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a repository it says so and reads nothing', (
    tester,
  ) async {
    final git = await _pump(tester, repoPath: null);
    expect(
      find.text('Open a repository to see its git settings.'),
      findsOneWidget,
    );
    expect(git.writes, isEmpty);
  });

  testWidgets('shows the value in effect and where it comes from', (
    tester,
  ) async {
    await _pump(
      tester,
      config:
          rec('global', '/home/u/.gitconfig', 'pull.rebase', 'yes') +
          rec('local', '.git/config', 'pull.rebase', 'false'),
    );
    expect(
      _inRow('pull.rebase', find.text('In effect: false — This repository')),
      findsOneWidget,
    );
    expect(
      _inRow('fetch.prune', find.text('In effect: not set — git\'s default')),
      findsOneWidget,
    );
    // Chips reflect this repository's own value.
    expect(_selected(tester, 'pull.rebase', 'false'), isTrue);
    expect(_selected(tester, 'fetch.prune', 'Inherit'), isTrue);
  });

  testWidgets('a value that is not a choice selects nothing and shows raw', (
    tester,
  ) async {
    await _pump(
      tester,
      config: rec('local', '.git/config', 'pull.rebase', 'interactive'),
    );
    for (final c in ['Inherit', 'false', 'true', 'merges']) {
      expect(_selected(tester, 'pull.rebase', c), isFalse, reason: c);
    }
    expect(
      _inRow(
        'pull.rebase',
        find.text('In effect: interactive — This repository'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('picking a value writes this repository by default', (
    tester,
  ) async {
    final git = await _pump(tester);
    await _tap(tester, _chip('rerere.enabled', 'true'));
    expect(git.writes, ['config --local --replace-all rerere.enabled true']);
  });

  testWidgets('Global writes the global config only once picked', (
    tester,
  ) async {
    final git = await _pump(
      tester,
      config:
          rec('global', '/g', 'core.autocrlf', 'input') +
          rec('global', '/g', 'fetch.prune', 'true'),
    );
    // Global's own value drives the chips once Global is the target.
    expect(_selected(tester, 'core.autocrlf', 'input'), isFalse);
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Global'));
    expect(_selected(tester, 'core.autocrlf', 'input'), isTrue);
    await _tap(tester, _chip('core.autocrlf', 'false'));
    await _tap(tester, _chip('fetch.prune', 'Inherit'));
    expect(git.writes, [
      'config --global --replace-all core.autocrlf false',
      'config --global --unset-all fetch.prune',
    ]);
  });

  testWidgets('tapping the value already set writes nothing', (tester) async {
    final git = await _pump(tester);
    await _tap(tester, _chip('fetch.prune', 'Inherit'));
    expect(git.writes, isEmpty);
  });

  testWidgets('Inherit removes this repository\'s value', (tester) async {
    final git = await _pump(
      tester,
      config: rec('local', '.git/config', 'commit.gpgsign', 'true'),
    );
    await _tap(tester, _chip('commit.gpgsign', 'Inherit'));
    expect(git.writes, ['config --local --unset-all commit.gpgsign']);
  });

  testWidgets('a write re-reads, so the row shows what git now says', (
    tester,
  ) async {
    final git = await _pump(tester);
    git.config = rec('local', '.git/config', 'fetch.prune', 'true');
    await _tap(tester, _chip('fetch.prune', 'true'));
    expect(
      _inRow('fetch.prune', find.text('In effect: true — This repository')),
      findsOneWidget,
    );
  });

  testWidgets('a name is saved on Enter; an emptied one is unset', (
    tester,
  ) async {
    final git = await _pump(
      tester,
      config: rec('local', '.git/config', 'user.name', 'Old Name'),
    );
    final field = _inRow('user.name', find.byType(TextField));
    expect(find.text('Old Name'), findsWidgets);
    await tester.enterText(field, '  New Name ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(git.writes, [
      'config --local --replace-all user.name New Name',
      'config --local --unset-all user.name',
    ]);
  });

  testWidgets('an unchanged name saves nothing', (tester) async {
    final git = await _pump(
      tester,
      config: rec('local', '.git/config', 'user.email', 'a@b'),
    );
    final field = _inRow('user.email', find.byType(TextField));
    await tester.enterText(field, 'a@b');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(git.writes, isEmpty);
  });

  testWidgets('an active profile is said to win over the identity', (
    tester,
  ) async {
    await _pump(tester, profile: _work);
    expect(
      find.text(
        'Commits made in Mergelio use the profile «Work»: '
        'Maria K <maria@work.com>. These values apply to git outside '
        'Mergelio.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no profile, no profile note', (tester) async {
    await _pump(tester);
    expect(find.textContaining('use the profile'), findsNothing);
  });

  testWidgets('pull.rebase says when the app pull strategy decides', (
    tester,
  ) async {
    await _pump(tester, pullStrategy: 'rebase');
    expect(
      _inRow('pull.rebase', find.textContaining('pulls with --rebase')),
      findsOneWidget,
    );
  });

  testWidgets('pull.rebase says it decides when the app merges', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      _inRow('pull.rebase', find.textContaining('this setting decides')),
      findsOneWidget,
    );
  });

  testWidgets('keys Mergelio handles itself say so', (tester) async {
    await _pump(tester);
    expect(
      _inRow('fetch.prune', find.textContaining('Mergelio always prunes')),
      findsOneWidget,
    );
    expect(
      _inRow(
        'push.autoSetupRemote',
        find.textContaining('Mergelio sets the upstream'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed write is reported with git\'s message', (tester) async {
    await _pump(tester, failWrites: true);
    await _tap(tester, _chip('rerere.enabled', 'true'));
    final toasts = _container.read(toastProvider);
    expect(
      toasts.map((t) => t.title),
      contains('Could not change rerere.enabled'),
    );
    expect(
      toasts.map((t) => t.description),
      contains('error: could not lock config file'),
    );
  });

  testWidgets('a config git cannot read says so instead of empty rows', (
    tester,
  ) async {
    await _pump(tester, failRead: true);
    expect(find.textContaining('fatal: bad config line 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('rcfg-fetch.prune')), findsNothing);
  });

  testWidgets('fits the dialog in Ukrainian at its narrowest', (tester) async {
    await _pump(
      tester,
      locale: const Locale('uk'),
      width: 520,
      profile: _work,
      config: rec(
        'global',
        '/a/very/long/path/to/.gitconfig',
        'user.name',
        'x',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Цей репозиторій'), findsWidgets);
  });

  Future<void> openPrefs(
    WidgetTester tester,
    GitService git,
    WorkspaceController Function() workspace,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          workspaceProvider.overrideWith((ref) => workspace()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPreferencesDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository'));
    await tester.pumpAndSettle();
  }

  testWidgets('the tab names the repository it edits', (tester) async {
    await openPrefs(
      tester,
      _FakeGit(''),
      () => WorkspaceController()..openRepo('/work/my-repo'),
    );
    expect(find.text('my-repo'), findsOneWidget);
    expect(find.text('/work/my-repo'), findsOneWidget);
  });

  testWidgets('a repository hidden behind the dashboard is not edited', (
    tester,
  ) async {
    final git = _FakeGit(rec('local', '.git/config', 'user.name', 'Lo Cal'));
    await openPrefs(
      tester,
      git,
      () => WorkspaceController()
        ..openRepo('/work/repo')
        ..showDashboard(),
    );
    expect(
      find.text('Open a repository to see its git settings.'),
      findsOneWidget,
    );
  });

  testWidgets('Preferences has a Repository tab for the active repository', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final git = _FakeGit(rec('local', '.git/config', 'user.name', 'Lo Cal'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          workspaceProvider.overrideWith(
            (ref) => WorkspaceController()..openRepo('/work/repo'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPreferencesDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository'));
    await tester.pumpAndSettle();
    expect(find.text('In effect: Lo Cal — This repository'), findsOneWidget);
  });

  testWidgets('quick changes are written one after another', (tester) async {
    final git = await _pump(tester);
    git.gate = Completer<void>();
    await tester.ensureVisible(_chip('rerere.enabled', 'true'));
    await tester.pumpAndSettle();
    await tester.tap(_chip('rerere.enabled', 'true'));
    await tester.pump();
    await tester.tap(_chip('fetch.prune', 'false'));
    await tester.pump();
    git.gate!.complete();
    await tester.pumpAndSettle();
    expect(git.writes, [
      'config --local --replace-all rerere.enabled true',
      'config --local --replace-all fetch.prune false',
    ]);
    expect(git.maxRunning, 1);
  });

  testWidgets('a name that failed to save goes back to the stored one', (
    tester,
  ) async {
    await _pump(
      tester,
      failWrites: true,
      config: rec('local', '.git/config', 'user.name', 'Stored'),
    );
    final field = _inRow('user.name', find.byType(TextField));
    await tester.enterText(field, 'Typed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'Stored');
  });

  testWidgets('changing another key keeps a name still being typed', (
    tester,
  ) async {
    await _pump(tester);
    final field = _inRow('user.name', find.byType(TextField));
    await tester.enterText(field, 'Half typed');
    await _tap(tester, _chip('rerere.enabled', 'true'));
    expect(tester.widget<TextField>(field).controller!.text, 'Half typed');
  });

  testWidgets('where writes go stays on screen at the bottom of the list', (
    tester,
  ) async {
    await _pump(tester, width: 560);
    tester.view.physicalSize = const Size(560, 460);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    final global = find.widgetWithText(ChoiceChip, 'Global');
    expect(global.hitTestable(), findsOneWidget);
  });

  testWidgets('a change asked for just before closing still lands', (
    tester,
  ) async {
    final git = await _pump(tester);
    git.gate = Completer<void>();
    await _tap(tester, _chip('rerere.enabled', 'true'));
    await tester.tap(_chip('fetch.prune', 'false'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    git.gate!.complete();
    await tester.pumpAndSettle();
    expect(git.writes, [
      'config --local --replace-all rerere.enabled true',
      'config --local --replace-all fetch.prune false',
    ]);
  });

  testWidgets('an unexpected error does not stop later changes', (
    tester,
  ) async {
    final git = await _pump(tester);
    git.throwOddly = true;
    await _tap(tester, _chip('rerere.enabled', 'true'));
    await _tap(tester, _chip('fetch.prune', 'false'));
    expect(git.writes, hasLength(2));
    expect(
      _container.read(toastProvider).map((t) => t.title),
      contains('Could not change rerere.enabled'),
    );
  });

  testWidgets('a name stored empty can be cleared', (tester) async {
    final git = await _pump(
      tester,
      config: rec('local', '.git/config', 'user.name', ''),
    );
    final field = _inRow('user.name', find.byType(TextField));
    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(git.writes, ['config --local --unset-all user.name']);
  });
}
