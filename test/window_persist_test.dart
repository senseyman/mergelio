// What the window listener writes, and when it stays quiet: a maximized or
// full-screen window must not overwrite the remembered "normal" rectangle.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/window_persist.dart';

void main() {
  late List<Rect> written;
  late Rect bounds;
  late bool maximized;
  late bool fullScreen;

  WindowGeometryPersist build() => WindowGeometryPersist(
    readBounds: () async => bounds,
    readMaximized: () async => maximized,
    readFullScreen: () async => fullScreen,
    write: written.add,
    debounce: const Duration(milliseconds: 10),
  );

  setUp(() {
    written = [];
    bounds = const Rect.fromLTWH(100, 80, 1440, 900);
    maximized = false;
    fullScreen = false;
  });

  // Long enough for the debounce plus the async reads to settle.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  test('writes the bounds when a resize ends', () async {
    build().onWindowResized();
    await settle();

    expect(written, [const Rect.fromLTWH(100, 80, 1440, 900)]);
  });

  test('writes the bounds when a move ends', () async {
    build().onWindowMoved();
    await settle();

    expect(written, [const Rect.fromLTWH(100, 80, 1440, 900)]);
  });

  // macOS emits `moved` from windowDidMove, which fires throughout a live
  // drag — not once at the end like `resized` does.
  test('collapses a stream of move-ended events into one write', () async {
    final p = build();

    p.onWindowMoved();
    p.onWindowMoved();
    p.onWindowMoved();
    await settle();

    expect(written, hasLength(1));
  });

  test('collapses a continuous drag into one write', () async {
    final p = build();

    p.onWindowMove();
    p.onWindowMove();
    p.onWindowResize();
    await settle();

    expect(written, hasLength(1));
  });

  test('writes the position the drag ended at', () async {
    final p = build();

    p.onWindowMove();
    bounds = const Rect.fromLTWH(300, 200, 1440, 900);
    p.onWindowMove();
    await settle();

    expect(written.single.topLeft, const Offset(300, 200));
  });

  test('keeps the normal rectangle while maximized', () async {
    maximized = true;

    build().onWindowResized();
    await settle();

    expect(written, isEmpty);
  });

  test('keeps the normal rectangle while full screen', () async {
    fullScreen = true;

    build().onWindowMoved();
    await settle();

    expect(written, isEmpty);
  });

  test('a disposed listener drops its pending write', () async {
    final p = build();

    p.onWindowMove();
    p.dispose();
    await settle();

    expect(written, isEmpty);
  });

  test('resumes writing after leaving maximized', () async {
    final p = build();
    maximized = true;
    p.onWindowResized();
    await settle();

    maximized = false;
    p.onWindowResized();
    await settle();

    expect(written, hasLength(1));
  });
}
