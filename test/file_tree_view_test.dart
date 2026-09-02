import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/common/file_tree_view.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppTokens.dark()]),
  home: Scaffold(body: child),
);

void main() {
  const paths = ['lib/ui/a.dart', 'lib/ui/b.dart', 'README.md'];

  testWidgets('flat mode renders every path once, no folder rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FileTreeView(
          paths: paths,
          tree: false,
          fileRow: (path, depth) => Text('$path@$depth'),
        ),
      ),
    );
    expect(find.text('lib/ui/a.dart@0'), findsOneWidget);
    expect(find.text('README.md@0'), findsOneWidget);
  });

  testWidgets('tree mode groups under a folder and collapses on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FileTreeView(
          paths: paths,
          tree: true,
          fileRow: (path, depth) => Text(path),
        ),
      ),
    );
    // Compacted folder row plus the two grouped files are visible.
    expect(find.text('lib/ui'), findsOneWidget);
    expect(find.text('lib/ui/a.dart'), findsOneWidget);
    expect(find.text('lib/ui/b.dart'), findsOneWidget);

    // Collapsing the folder hides its files but keeps the folder row.
    await tester.tap(find.text('lib/ui'));
    await tester.pump();
    expect(find.text('lib/ui'), findsOneWidget);
    expect(find.text('lib/ui/a.dart'), findsNothing);
    expect(find.text('lib/ui/b.dart'), findsNothing);
  });
}
