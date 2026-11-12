import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
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
