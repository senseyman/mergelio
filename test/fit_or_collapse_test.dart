import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/common/fit_or_collapse.dart';

Widget _box(double maxWidth) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 40),
      child: FitOrCollapse(
        full: Row(
          key: const ValueKey('full'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              const ColoredBox(
                color: Color(0xFF000000),
                child: SizedBox(width: 50, height: 20),
              ),
          ],
        ),
        compact: const ColoredBox(
          key: ValueKey('compact'),
          color: Color(0xFF000000),
          child: SizedBox(width: 30, height: 20),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the full child when it fits', (tester) async {
    await tester.pumpWidget(_box(200));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FitOrCollapse)).width, 200);
    expect(find.byKey(const ValueKey('full')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('compact')).hitTestable(), findsNothing);
  });

  testWidgets('shows the compact child when the full one would overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_box(199));
    // The full row is laid out to measure it but never painted, so its
    // overflow is not reported.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FitOrCollapse)).width, 30);
    expect(find.byKey(const ValueKey('compact')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('full')).hitTestable(), findsNothing);
  });

  testWidgets('switches back once there is room again', (tester) async {
    await tester.pumpWidget(_box(100));
    expect(find.byKey(const ValueKey('compact')).hitTestable(), findsOneWidget);
    await tester.pumpWidget(_box(400));
    expect(find.byKey(const ValueKey('full')).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('compact')).hitTestable(), findsNothing);
  });
}
