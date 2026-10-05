import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

Future<void> _pump(WidgetTester t, {bool reduceMotion = false}) => t.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const Scaffold(body: ForgeLoadingRow()),
    ),
  ),
);

double _opacity(WidgetTester t) => t
    .widget<Opacity>(
      find.descendant(
        of: find.byType(ForgeLoadingRow),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  testWidgets('draws placeholder rows rather than a spinner', (t) async {
    await _pump(t);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the placeholders breathe while loading', (t) async {
    await _pump(t);
    final start = _opacity(t);
    await t.pump(const Duration(milliseconds: 600));

    expect(_opacity(t), isNot(start));
    expect(t.hasRunningAnimations, isTrue);
  });

  testWidgets('reduced motion holds the placeholders still', (t) async {
    await _pump(t, reduceMotion: true);
    final start = _opacity(t);
    await t.pump(const Duration(milliseconds: 600));

    expect(_opacity(t), start);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('placeholders fit the narrowest sidebar', (t) async {
    t.view.physicalSize = const Size(264, 200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t);

    expect(t.takeException(), isNull);
  });
}
