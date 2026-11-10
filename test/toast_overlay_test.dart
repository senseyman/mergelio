import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/ui/common/toast_overlay.dart';

/// The bottom-right toast stack: what it shows, its action button, and the
/// coloured edge that tells success from failure.
void main() {
  late ProviderContainer c;
  final tokens = AppTokens.dark();

  Future<void> pump(WidgetTester tester) async {
    c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData(extensions: [tokens]),
          home: const Scaffold(body: Stack(children: [ToastOverlay()])),
        ),
      ),
    );
  }

  ToastController toasts() => c.read(toastProvider.notifier);

  /// Colour of the left edge drawn on the toast whose title is [title].
  Color edgeOf(WidgetTester tester, String title) {
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first,
    );
    final border =
        (box.foregroundDecoration! as BoxDecoration).border! as Border;
    return border.left.color;
  }

  testWidgets('shows nothing without toasts', (tester) async {
    await pump(tester);
    expect(find.byType(Positioned), findsNothing);
  });

  testWidgets('shows title and description, newest last', (tester) async {
    await pump(tester);
    toasts().show('Pushed', description: 'main → origin/main');
    toasts().show('Fetched');
    await tester.pump();

    expect(find.text('Pushed'), findsOneWidget);
    expect(find.text('main → origin/main'), findsOneWidget);
    expect(find.text('Fetched'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Pushed')).dy,
      lessThan(tester.getTopLeft(find.text('Fetched')).dy),
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a toast without description shows only its title', (
    tester,
  ) async {
    await pump(tester);
    toasts().show('Only title');
    await tester.pump();
    final column = tester.widget<Column>(
      find
          .ancestor(of: find.text('Only title'), matching: find.byType(Column))
          .first,
    );
    expect(column.children, hasLength(1));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the edge colour follows the kind', (tester) async {
    await pump(tester);
    toasts()
      ..show('ok', kind: ToastKind.success)
      ..show('careful', kind: ToastKind.warning)
      ..show('broke', kind: ToastKind.error)
      ..show('fyi');
    await tester.pump();

    expect(edgeOf(tester, 'ok'), tokens.success);
    expect(edgeOf(tester, 'careful'), tokens.warning);
    expect(edgeOf(tester, 'broke'), tokens.danger);
    expect(edgeOf(tester, 'fyi'), tokens.accent);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the action runs and dismisses its toast', (tester) async {
    await pump(tester);
    var undone = 0;
    toasts().show(
      'Deleted branch',
      action: ToastAction('Undo', () => undone++),
    );
    toasts().show('Other');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await tester.pump();

    expect(undone, 1);
    expect(find.text('Deleted branch'), findsNothing);
    expect(find.text('Other'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('toasts without an action have no button', (tester) async {
    await pump(tester);
    toasts().show('Plain');
    await tester.pump();
    expect(find.byType(TextButton), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('toasts leave on their own, actionable ones later', (
    tester,
  ) async {
    await pump(tester);
    toasts().show('Plain');
    toasts().show('Actionable', action: ToastAction('Undo', () {}));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 3500));
    expect(find.text('Plain'), findsNothing);
    expect(find.text('Actionable'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Actionable'), findsNothing);
    expect(find.byType(Positioned), findsNothing);
  });
}
