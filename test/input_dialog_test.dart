import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/common/dialogs.dart';

void main() {
  Widget harness(void Function(BuildContext) onTap) => MaterialApp(
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onTap(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('confirm returns the entered value without a disposed-controller '
      'crash after the exit animation', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      harness((c) async {
        result = await showInputDialog(c, title: 'Name', label: 'Branch');
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'feature/x');
    await tester.tap(find.text('OK'));
    // pumpAndSettle drives the dialog's reverse (exit) transition — the crash
    // reproduced here when the controller was disposed too early.
    await tester.pumpAndSettle();

    expect(result, 'feature/x');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel returns null and survives the exit animation', (
    tester,
  ) async {
    String? result = 'unset';
    await tester.pumpWidget(
      harness((c) async {
        result = await showInputDialog(c, title: 'Name');
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'typed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
