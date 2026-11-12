import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/net/proxy.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/network.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/network_tab.dart';

Future<SettingsController> _pumpTab(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(),
  String? gitProxy,
  Map<String, String> env = const {},
  String gitVersion = 'git version 2.50.0',
  String? repoPath,
  List<String> sshRemotes = const [],
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = SettingsController(InMemorySettingsRepository(), settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => controller),
        // Widget tests cannot run git; the policy's other inputs stay real so
        // the tab is shown what the provider would really hand it.
        gitHttpProxyProvider.overrideWith((ref) async => gitProxy),
        proxyEnvironmentProvider.overrideWithValue(env),
        gitVersionProvider.overrideWith((ref) async => gitVersion),
        sshRemotesProvider.overrideWith((ref, path) async => sshRemotes),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: NetworkTab(repoPath: repoPath)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('says which proxy is used and where it came from', (
    tester,
  ) async {
    await _pumpTab(tester, gitProxy: 'http://me:secret@proxy.corp:3128');
    expect(find.textContaining('proxy.corp:3128'), findsOneWidget);
    expect(find.textContaining('http.proxy'), findsWidgets);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('nothing configured reads as direct', (tester) async {
    await _pumpTab(tester);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyStatusDirect), findsOneWidget);
  });

  testWidgets('an unusable proxy is called out', (tester) async {
    await _pumpTab(tester, env: {'ALL_PROXY': 'socks5://127.0.0.1:9050'});
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyStatusUnsupported('ALL_PROXY')), findsOneWidget);
  });

  testWidgets('says when proxy credentials cannot be sent', (tester) async {
    await _pumpTab(tester, gitProxy: 'http://u:se%3Bcret@proxy.corp:3128');
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyCredentialsDropped('http.proxy')), findsOneWidget);
    expect(find.textContaining('cret'), findsNothing);
  });

  testWidgets('each mode says what it covers', (tester) async {
    final settings = await _pumpTab(tester);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyAutoNote), findsOneWidget);
    expect(find.text(l.proxyManualNote), findsNothing);
    settings.setProxyMode(ProxyMode.manual);
    await tester.pump();
    expect(find.text(l.proxyManualNote), findsOneWidget);
    expect(find.text(l.proxyAutoNote), findsNothing);
  });

  testWidgets('the git switch is offered only where it changes something', (
    tester,
  ) async {
    final settings = await _pumpTab(tester);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyForGit), findsNothing);
    for (final mode in [ProxyMode.manual, ProxyMode.off]) {
      settings.setProxyMode(mode);
      await tester.pump();
      expect(find.text(l.proxyForGit), findsOneWidget, reason: mode.name);
    }
  });

  testWidgets('the git switch writes the setting and changes the git note', (
    tester,
  ) async {
    final settings = await _pumpTab(
      tester,
      settings: const AppSettings(proxyMode: 'off'),
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyGitNote), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.state.proxyForGit, isTrue);
    expect(find.text(l.proxyGitNote), findsNothing);
    expect(find.text(l.proxyForGitNote), findsOneWidget);
  });

  testWidgets('says which remotes of the open repo the proxy cannot cover', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      settings: const AppSettings(proxyMode: 'manual', proxyForGit: true),
      repoPath: '/src/go-ethereum',
      sshRemotes: ['origin', 'fork'],
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l.proxySshRemotes(2, 'go-ethereum', 'origin, fork')),
      findsOneWidget,
    );
  });

  test('one ssh remote reads in the singular', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.proxySshRemotes(1, 'r', 'origin'), contains('origin connects'));
    expect(en.proxySshRemotes(2, 'r', 'a, b'), contains('a, b connect '));
  });

  testWidgets('git is not asked its version while the switch is off', (
    tester,
  ) async {
    var asked = 0;
    final controller = SettingsController(
      InMemorySettingsRepository(),
      const AppSettings(proxyMode: 'manual'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => controller),
          gitHttpProxyProvider.overrideWith((ref) async => null),
          proxyEnvironmentProvider.overrideWithValue(const {}),
          gitVersionProvider.overrideWith((ref) async {
            asked++;
            return 'git version 2.50.0';
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: NetworkTab()),
        ),
      ),
    );
    await tester.pump();
    expect(asked, 0);
    controller.setProxyForGit(true);
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('no ssh hint while git keeps its own proxy settings', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      settings: const AppSettings(proxyMode: 'manual'),
      repoPath: '/src/r',
      sshRemotes: ['origin'],
    );
    expect(find.textContaining('origin'), findsNothing);
  });

  testWidgets('a git too old for the switch is called out', (tester) async {
    await _pumpTab(
      tester,
      settings: const AppSettings(proxyMode: 'off', proxyForGit: true),
      gitVersion: 'git version 2.30.9',
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.proxyForGitTooOld('2.30.9')), findsOneWidget);
  });

  testWidgets('picking No proxy turns it off', (tester) async {
    final settings = await _pumpTab(tester, gitProxy: 'proxy.corp:3128');
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l.proxyModeOff));
    await tester.pump();
    await tester.pump();
    expect(settings.state.proxyMode, ProxyMode.off.name);
    expect(find.text(l.proxyStatusDirect), findsOneWidget);
  });

  testWidgets('the url field shows only in manual mode and saves on submit', (
    tester,
  ) async {
    final settings = await _pumpTab(tester);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(l.proxyModeManual));
    await tester.pump();
    await tester.enterText(find.byType(TextField), ' http://typed:8080 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(settings.state.proxyMode, 'manual');
    expect(settings.state.proxyUrl, 'http://typed:8080');
    expect(find.text(l.proxyStatusVia('typed:8080')), findsOneWidget);
  });

  testWidgets('fits the narrowest preferences width', (tester) async {
    await _pumpTab(tester, gitProxy: 'socks5://h:1');
    for (final width in [900.0, 560.0, 420.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$width');
    }
  });
}
