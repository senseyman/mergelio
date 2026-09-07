import 'dart:math' as math;
import 'dart:ui';

/// Where the window should open: a size, and a position that is `null` when
/// the window manager should centre it instead.
class WindowPlacement {
  final Size size;
  final Offset? position;
  const WindowPlacement({required this.size, this.position});
}

/// One connected display, as the platform reports it.
class DisplayInfo {
  /// Full size of the display.
  final Size size;

  /// Top-left corner of the usable area, or `null` when the platform could
  /// not place the display.
  final Offset? visiblePosition;

  /// Usable area — what is left after the menu bar, dock or taskbar. Falls
  /// back to [size] when the platform does not report it.
  final Size? visibleSize;

  /// Ratio between physical and logical pixels on this display.
  final double? scaleFactor;

  final bool isPrimary;

  const DisplayInfo({
    required this.size,
    this.visiblePosition,
    this.visibleSize,
    this.scaleFactor,
    this.isPrimary = false,
  });
}

/// Fraction of a display the window falls back to when the remembered size no
/// longer fits on it.
const _resetFraction = 0.8;

/// Usable rectangles of [displays], primary first — [resolveWindowPlacement]
/// falls back to the head of the list when it cannot tell which display the
/// window belongs on. Displays the platform could not place are dropped
/// rather than guessed at, since guessing puts them on top of the primary.
List<Rect> displayBounds(List<DisplayInfo> displays) {
  final placeable = displays.where((d) => d.visiblePosition != null).toList();
  // Stable: the primary moves to the front, the rest keep platform order.
  placeable.sort((a, b) {
    if (a.isPrimary == b.isPrimary) return 0;
    return a.isPrimary ? -1 : 1;
  });
  return [
    for (final d in placeable) d.visiblePosition! & (d.visibleSize ?? d.size),
  ];
}

/// Whether a remembered position can be compared against [displays] at all.
///
/// Windows reports each monitor's bounds scaled by that monitor's own DPI,
/// while window bounds come back scaled by the single ratio of the Flutter
/// view. The two agree until monitors with different scaling are mixed, and
/// from then on a remembered position would be measured against the wrong
/// ruler — better to centre the window than to place it on the wrong screen.
bool positionIsTrustworthy(
  List<DisplayInfo> displays, {
  required bool isWindows,
}) {
  if (!isWindows) return true;
  final scales = displays.map((d) => d.scaleFactor ?? 1).toSet();
  return scales.length <= 1;
}

/// Turns the remembered geometry into a placement that is guaranteed to land
/// on a display the user can actually see.
///
/// [displays] are visible bounds — the area left after the menu bar, dock or
/// taskbar — with the primary display first, as [displayBounds] returns them.
/// Monitors get unplugged and resolutions change between runs, so a
/// remembered rectangle is treated as a hint, never as a promise. Under
/// Wayland the compositor ignores client positioning outright, so only the
/// size survives there.
WindowPlacement resolveWindowPlacement({
  required double? x,
  required double? y,
  required Size savedSize,
  required Size minimumSize,
  required List<Rect> displays,
}) {
  // The window manager enforces the minimum after the fact, so a smaller
  // remembered size would grow back and overhang whatever we clamped it to.
  final wanted = Size(
    math.max(savedSize.width, minimumSize.width),
    math.max(savedSize.height, minimumSize.height),
  );

  // No display information (the platform query failed): nothing to validate
  // against, so let the window manager centre the window itself.
  if (displays.isEmpty) return WindowPlacement(size: wanted);

  final saved = (x != null && y != null)
      ? Rect.fromLTWH(x, y, wanted.width, wanted.height)
      : null;

  // The display holding most of the remembered window. Absent when the window
  // was last on a monitor that is no longer connected.
  Rect? host;
  if (saved != null) {
    var bestArea = 0.0;
    for (final display in displays) {
      final overlap = display.intersect(saved);
      if (overlap.width <= 0 || overlap.height <= 0) continue;
      final area = overlap.width * overlap.height;
      if (area > bestArea) {
        bestArea = area;
        host = display;
      }
    }
  }
  final target = host ?? displays.first;

  // The remembered size outgrew the display (smaller monitor, or a screen
  // resolution change): start over at a fraction of the screen, centred.
  if (wanted.width > target.width || wanted.height > target.height) {
    final size = Size(
      math.max(target.width * _resetFraction, minimumSize.width),
      math.max(target.height * _resetFraction, minimumSize.height),
    );
    // A display narrower or shorter than the minimum leaves no room to
    // centre in; pin to the top-left corner so the window stays reachable.
    return WindowPlacement(
      size: size,
      position: Offset(
        math.max(target.left, target.left + (target.width - size.width) / 2),
        math.max(target.top, target.top + (target.height - size.height) / 2),
      ),
    );
  }

  // Either nothing was remembered, or the host display is gone — centre.
  if (host == null) return WindowPlacement(size: wanted);

  // Pull the window fully inside its display: the size fits, so both clamp
  // ranges are non-empty.
  return WindowPlacement(
    size: wanted,
    position: Offset(
      x!.clamp(target.left, target.right - wanted.width),
      y!.clamp(target.top, target.bottom - wanted.height),
    ),
  );
}
