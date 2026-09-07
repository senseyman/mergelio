import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

/// Records the window geometry so the next launch reopens where the user left
/// off. Reads and writes are injected, which keeps the timing rules testable
/// without a live window.
///
/// Only `onWindowResized` is a true end-of-gesture event (macOS raises it from
/// `windowDidEndLiveResize`, Windows from `WM_EXITSIZEMOVE`), so that one
/// writes straight through and a quick quit cannot drop the final size. Every
/// other callback fires repeatedly mid-drag — macOS raises `moved` from
/// `windowDidMove` on every step — so those go through a debounce instead of
/// writing a row per frame.
class WindowGeometryPersist with WindowListener {
  final Future<Rect> Function() readBounds;
  final Future<bool> Function() readMaximized;
  final Future<bool> Function() readFullScreen;
  final void Function(Rect) write;
  final Duration debounce;

  Timer? _timer;

  WindowGeometryPersist({
    required this.readBounds,
    required this.readMaximized,
    required this.readFullScreen,
    required this.write,
    this.debounce = const Duration(milliseconds: 300),
  });

  Future<void> _persistNow() async {
    _timer?.cancel();
    // A maximized or full-screen window fills the screen; remembering that as
    // the geometry would lose the rectangle the user actually arranged.
    if (await readMaximized() || await readFullScreen()) return;
    write(await readBounds());
  }

  void _persistSoon() {
    _timer?.cancel();
    _timer = Timer(debounce, _persistNow);
  }

  @override
  void onWindowResized() => unawaited(_persistNow());

  @override
  void onWindowMoved() => _persistSoon();

  @override
  void onWindowResize() => _persistSoon();

  @override
  void onWindowMove() => _persistSoon();

  /// Drops a pending write, so shutdown can't land one in a closing database.
  void dispose() => _timer?.cancel();
}
