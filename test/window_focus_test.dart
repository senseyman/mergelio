import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/window_focus.dart';

void main() {
  test('tracker mirrors window focus events', () {
    final seen = <bool>[];
    final t = WindowFocusTracker(seen.add);

    t.onWindowBlur();
    t.onWindowFocus();
    t.onWindowMinimize();
    t.onWindowRestore();

    expect(seen, [false, true, false, true]);
  });
}
