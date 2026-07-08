import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';

Widget _app(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Text('${l.opFetch}|${l.prefsLanguage}');
    },
  ),
);

void main() {
  test('both en and uk are supported locales', () {
    final codes = AppLocalizations.supportedLocales.map((l) => l.languageCode);
    expect(codes, containsAll(['en', 'uk']));
  });

  testWidgets('English locale renders English strings', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Fetch|Language'), findsOneWidget);
  });

  testWidgets('Ukrainian locale renders Ukrainian strings', (tester) async {
    await tester.pumpWidget(_app(const Locale('uk')));
    await tester.pumpAndSettle();
    expect(find.text('Отримати|Мова'), findsOneWidget);
  });
}
