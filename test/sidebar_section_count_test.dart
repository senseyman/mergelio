import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/sidebar_section.dart';

Future<void> pumpHeader(WidgetTester tester, {required int? count}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: Scaffold(
        body: SidebarSection(
          id: 'demo',
          icon: Icons.history,
          label: 'Demo',
          count: count,
          emptyLabel: 'Nothing here',
          open: true,
          onToggle: () {},
          children: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows how many rows a section holds', (tester) async {
    await pumpHeader(tester, count: 3);

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('shows no number when the count is unknown', (tester) async {
    // A section that has not read its contents yet has no count to show.
    // Rendering one anyway would claim the section is empty.
    await pumpHeader(tester, count: null);

    expect(find.text('null'), findsNothing);
    expect(find.text('0'), findsNothing);
  });
}
