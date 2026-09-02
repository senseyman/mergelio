import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/diff/linked_scroll.dart';

void main() {
  late LinkedScrollController controller;

  Widget twoLists({int count = 200}) => MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          for (final side in ['L', 'R'])
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(height: 20, child: Text('$side$i')),
              ),
            ),
        ],
      ),
    ),
  );

  setUp(() => controller = LinkedScrollController());
  tearDown(() => controller.dispose());

  testWidgets('two lists share one controller without asserting', (
    tester,
  ) async {
    await tester.pumpWidget(twoLists());
    expect(controller.positions.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling one list moves the other', (tester) async {
    await tester.pumpWidget(twoLists());

    await tester.drag(find.text('L0'), const Offset(0, -300));
    await tester.pumpAndSettle();

    final offsets = controller.positions.map((p) => p.pixels).toSet();
    expect(offsets.length, 1, reason: 'both sides sit at the same offset');
    expect(offsets.single, greaterThan(0));
  });

  testWidgets('either side can drive the other', (tester) async {
    await tester.pumpWidget(twoLists());

    // Drive from the right-hand list this time.
    await tester.drag(find.text('R0'), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(controller.positions.map((p) => p.pixels).toSet().length, 1);
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('a list attached later starts at the shared offset', (
    tester,
  ) async {
    await tester.pumpWidget(twoLists());
    await tester.drag(find.text('L0'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final shared = controller.offset;

    // Rebuilding with a different item count re-attaches the positions.
    await tester.pumpWidget(twoLists(count: 201));
    await tester.pumpAndSettle();

    for (final p in controller.positions) {
      expect(p.pixels, shared);
    }
  });

  testWidgets('a shorter side clamps instead of overscrolling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: 200,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 20, child: Text('L$i')),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: 3,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 20, child: Text('R$i')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.text('L0'), const Offset(0, -400));
    await tester.pumpAndSettle();

    for (final p in controller.positions) {
      expect(p.pixels, lessThanOrEqualTo(p.maxScrollExtent));
    }
    expect(tester.takeException(), isNull);
  });
}
