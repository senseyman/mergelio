import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/common/change_file_row.dart';

Future<void> _pump(WidgetTester tester, {required bool selected}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChangeFileRow(
            file: const CommitFileChange(
              path: 'lib/a.dart',
              change: GitChange.modified,
            ),
            repoPath: '/repo',
            selected: selected,
            onTap: () {},
          ),
        ),
      ),
    );

/// The fill behind the row, which is what marks it as the one being viewed.
Color? _fill(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(ChangeFileRow),
        matching: find.byType(Material),
      ),
    )
    .color;

void main() {
  testWidgets('a selected row is filled like the working tree\'s', (
    tester,
  ) async {
    await _pump(tester, selected: true);

    expect(_fill(tester), AppTokens.dark().active);
    expect(
      tester.getSemantics(find.text('lib/a.dart')),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('any other row is left clear', (tester) async {
    await _pump(tester, selected: false);

    expect(_fill(tester), Colors.transparent);
    expect(
      tester.getSemantics(find.text('lib/a.dart')),
      isNot(isSemantics(isSelected: true)),
    );
  });
}
