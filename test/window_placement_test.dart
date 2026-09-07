import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/window_placement.dart';

void main() {
  const minimum = Size(960, 600);
  // A single 1920x1080 display at the origin, minus a 25px menu bar.
  const laptop = Rect.fromLTWH(0, 25, 1920, 1055);
  // A second display sitting to the right of [laptop].
  const external = Rect.fromLTWH(1920, 0, 2560, 1440);

  WindowPlacement resolve({
    double? x,
    double? y,
    Size saved = const Size(1440, 900),
    List<Rect> displays = const [laptop],
  }) => resolveWindowPlacement(
    x: x,
    y: y,
    savedSize: saved,
    minimumSize: minimum,
    displays: displays,
  );

  group('resolveWindowPlacement', () {
    test('centres when no position was ever saved', () {
      final p = resolve();

      expect(p.position, isNull);
      expect(p.size, const Size(1440, 900));
    });

    test('keeps a position that is fully on a display', () {
      final p = resolve(x: 100, y: 80);

      expect(p.position, const Offset(100, 80));
      expect(p.size, const Size(1440, 900));
    });

    test(
      'clamps a window hanging off the right edge back onto its display',
      () {
        final p = resolve(x: 1800, y: 80);

        expect(p.position, const Offset(480, 80));
      },
    );

    test('clamps a window pushed above the visible area', () {
      final p = resolve(x: 100, y: -200);

      expect(p.position, const Offset(100, 25));
    });

    test('centres when the saved display is gone', () {
      // Saved on the external display, which is no longer connected.
      final p = resolve(x: 2400, y: 300);

      expect(p.position, isNull);
    });

    test('picks the display holding most of the saved window', () {
      final p = resolve(x: 2000, y: 100, displays: const [laptop, external]);

      expect(p.position, const Offset(2000, 100));
    });

    test('shrinks to 80% centred when the saved size exceeds the display', () {
      final p = resolve(x: 0, y: 25, saved: const Size(3000, 2000));

      // 80% of 1920x1055, centred inside the display's visible bounds.
      expect(p.size, const Size(1536, 844));
      expect(p.position, const Offset(192, 130.5));
    });

    test('keeps a saved size that exactly fills the display', () {
      final p = resolve(x: 0, y: 25, saved: const Size(1920, 1055));

      expect(p.size, const Size(1920, 1055));
      expect(p.position, const Offset(0, 25));
    });

    test('shrinks against the display the oversized window sits on', () {
      final p = resolve(
        x: 2000,
        y: 100,
        saved: const Size(2600, 1500),
        displays: const [laptop, external],
      );

      // 80% of the 2560x1440 external display, centred on it.
      expect(p.size, const Size(2048, 1152));
      expect(p.position, const Offset(2176, 144));
    });

    test('never shrinks below the minimum size', () {
      // 80% of 1000x700 is 800x560, both under the 960x600 floor.
      final p = resolve(
        x: 0,
        y: 0,
        saved: const Size(4000, 3000),
        displays: const [Rect.fromLTWH(0, 0, 1000, 700)],
      );

      expect(p.size, minimum);
    });

    test('drops the saved position when the size is reset', () {
      final p = resolve(x: 600, y: 400, saved: const Size(3000, 2000));

      expect(p.position, isNot(const Offset(600, 400)));
    });

    test('centres with the saved size when no display can be read', () {
      final p = resolve(x: 100, y: 80, displays: const []);

      expect(p.position, isNull);
      expect(p.size, const Size(1440, 900));
    });

    test('lifts a saved size below the minimum up to the floor', () {
      final p = resolve(x: 100, y: 80, saved: const Size(400, 300));

      expect(p.size, minimum);
    });

    test('keeps the reset window on screen on a display narrower than the '
        'minimum', () {
      // 80% of 900 is under the 960 floor, so the centred window would start
      // at -30 and hang off the left edge.
      final p = resolve(
        x: 0,
        y: 0,
        saved: const Size(4000, 3000),
        displays: const [Rect.fromLTWH(0, 0, 900, 700)],
      );

      expect(p.size, minimum);
      expect(p.position, const Offset(0, 50));
    });
  });

  group('displayBounds', () {
    test('puts the primary display first, whatever order it arrived in', () {
      final bounds = displayBounds(const [
        DisplayInfo(
          size: Size(2560, 1440),
          visiblePosition: Offset(1920, 0),
          visibleSize: Size(2560, 1440),
        ),
        DisplayInfo(
          size: Size(1920, 1080),
          visiblePosition: Offset.zero,
          visibleSize: Size(1920, 1055),
          isPrimary: true,
        ),
      ]);

      expect(bounds.first, const Rect.fromLTWH(0, 0, 1920, 1055));
      expect(bounds, hasLength(2));
    });

    test('drops a display the platform could not place', () {
      final bounds = displayBounds(const [DisplayInfo(size: Size(1920, 1080))]);

      expect(bounds, isEmpty);
    });

    test('falls back to the full size when the visible size is unknown', () {
      final bounds = displayBounds(const [
        DisplayInfo(size: Size(1920, 1080), visiblePosition: Offset.zero),
      ]);

      expect(bounds.single, const Rect.fromLTWH(0, 0, 1920, 1080));
    });
  });

  group('positionIsTrustworthy', () {
    const hidpi = DisplayInfo(
      size: Size(1920, 1080),
      visiblePosition: Offset.zero,
      scaleFactor: 1.5,
      isPrimary: true,
    );
    const standard = DisplayInfo(
      size: Size(1920, 1080),
      visiblePosition: Offset(1920, 0),
      scaleFactor: 1,
    );

    test('trusts a single display', () {
      expect(positionIsTrustworthy(const [hidpi], isWindows: true), isTrue);
    });

    test('trusts displays that share a scale factor', () {
      expect(
        positionIsTrustworthy(const [standard, standard], isWindows: true),
        isTrue,
      );
    });

    // On Windows the display list is scaled per monitor while window bounds
    // use one ratio, so mixed scaling puts the two in different spaces.
    test('distrusts mixed scale factors on Windows', () {
      expect(
        positionIsTrustworthy(const [hidpi, standard], isWindows: true),
        isFalse,
      );
    });

    test('trusts mixed scale factors elsewhere', () {
      expect(
        positionIsTrustworthy(const [hidpi, standard], isWindows: false),
        isTrue,
      );
    });
  });
}
