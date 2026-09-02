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

/// Renders one localised string, chosen by [pick], under [locale].
Widget _pluralApp(Locale locale, String Function(AppLocalizations) pick) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Text(pick(AppLocalizations.of(context))),
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

  // Ukrainian puts 1, 21, 31 … in the same plural category, so a form that
  // hardcodes "1" instead of interpolating the count reads "1 commit" for 21
  // of them. English never shows that, because its `one` category is only 1.
  group('unpushed-commit plural', () {
    Future<String> render(WidgetTester tester, Locale locale, int n) async {
      await tester.pumpWidget(
        _pluralApp(locale, (l) => l.sbResetUnpushedBody(n, 'main')),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.byType(Text)).data!;
    }

    testWidgets('English counts every quantity', (tester) async {
      expect(await render(tester, const Locale('en'), 1), startsWith('1 '));
      expect(await render(tester, const Locale('en'), 21), startsWith('21 '));
    });

    testWidgets('Ukrainian names the count in every form', (tester) async {
      for (final n in [1, 3, 5, 21]) {
        expect(
          await render(tester, const Locale('uk'), n),
          startsWith('$n '),
          reason: 'uk plural for $n must show the number, not a literal',
        );
      }
    });
  });
}
