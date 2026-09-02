import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/palette/command_palette.dart';

void main() {
  testWidgets('filters commands and runs the chosen one', (tester) async {
    var ran = '';
    final cmds = [
      PaletteCommand('Fetch', Icons.download, () async => ran = 'fetch'),
      PaletteCommand('Push', Icons.upload, () async => ran = 'push'),
      PaletteCommand(
        'Checkout: main',
        Icons.call_split,
        () async => ran = 'checkout',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCommandPalette(ctx, commands: cmds),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // All commands shown initially.
    expect(find.text('Fetch'), findsOneWidget);
    expect(find.text('Checkout: main'), findsOneWidget);

    // Fuzzy-filter to the checkout command and run it.
    await tester.enterText(find.byType(TextField), 'chkm');
    await tester.pumpAndSettle();
    expect(find.text('Fetch'), findsNothing);
    await tester.tap(find.text('Checkout: main'));
    await tester.pumpAndSettle();
    expect(ran, 'checkout');
  });
}
