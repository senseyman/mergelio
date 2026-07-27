import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/workspace/remote_dialog.dart';

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

  testWidgets('returns the entered name and URL', (tester) async {
    RemoteEdit? result;
    await tester.pumpWidget(
      harness((c) async {
        result = await showRemoteDialog(
          c,
          title: 'Add remote',
          confirmLabel: 'Add',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(remoteNameFieldKey), 'upstream');
    await tester.enterText(
      find.byKey(remoteUrlFieldKey),
      'https://example.com/u.git',
    );
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(result?.name, 'upstream');
    expect(result?.url, 'https://example.com/u.git');
    expect(tester.takeException(), isNull);
  });

  testWidgets('refuses a name another remote already uses', (tester) async {
    RemoteEdit? result;
    await tester.pumpWidget(
      harness((c) async {
        result = await showRemoteDialog(
          c,
          title: 'Add remote',
          confirmLabel: 'Add',
          existing: const ['origin'],
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(remoteNameFieldKey), 'origin');
    await tester.enterText(
      find.byKey(remoteUrlFieldKey),
      'https://example.com/o.git',
    );
    await tester.pump();

    expect(find.text('A remote named origin already exists'), findsOneWidget);

    // Confirm is disabled while invalid, so the dialog stays open.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byKey(remoteNameFieldKey), findsOneWidget);
  });

  testWidgets('lets an edited remote keep its own name', (tester) async {
    RemoteEdit? result;
    await tester.pumpWidget(
      harness((c) async {
        result = await showRemoteDialog(
          c,
          title: 'Edit remote',
          initialName: 'origin',
          initialUrl: 'https://example.com/o.git',
          existing: const ['origin'],
          current: 'origin',
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(remoteUrlFieldKey),
      'https://example.com/new.git',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.name, 'origin');
    expect(result?.url, 'https://example.com/new.git');
  });
}
