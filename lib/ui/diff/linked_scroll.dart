import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A [ScrollController] that keeps every scroll view attached to it at the same
/// offset.
///
/// The plain controller allows several attached positions but exposes only one,
/// and nothing keeps them together — reading [offset] with two attached even
/// asserts. This one mirrors any movement onto the others, which is what lets
/// the two columns of a split diff scroll vertically as a single surface while
/// each keeps its own horizontal scroll.
class LinkedScrollController extends ScrollController {
  LinkedScrollController({super.initialScrollOffset, super.debugLabel});

  /// Guards the mirroring: moving the other positions notifies their listeners
  /// in turn, which would otherwise bounce straight back.
  bool _mirroring = false;

  /// Last offset the group settled on, so a position attached later — a column
  /// rebuilt while the diff is scrolled — starts where the others already are.
  double _offset = 0;

  final _listeners = <ScrollPosition, VoidCallback>{};

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    void listener() => _mirror(position);
    _listeners[position] = listener;
    position.addListener(listener);
  }

  @override
  void detach(ScrollPosition position) {
    final listener = _listeners.remove(position);
    if (listener != null) position.removeListener(listener);
    super.detach(position);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => ScrollPositionWithSingleContext(
    physics: physics,
    context: context,
    initialPixels: positions.isEmpty ? initialScrollOffset : _offset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );

  /// The shared offset. Unlike [ScrollController.offset] this does not require
  /// exactly one attached position, which is the whole point of the group.
  @override
  double get offset => positions.isEmpty ? _offset : positions.first.pixels;

  /// Any attached position will do: they are held at the same offset, so a
  /// scrollbar reading this one describes the group. The base implementation
  /// asserts on a single position, which this controller exists to allow.
  @override
  ScrollPosition get position => positions.first;

  void _mirror(ScrollPosition source) {
    if (_mirroring) return;
    _mirroring = true;
    try {
      _offset = source.pixels;
      for (final other in positions) {
        if (identical(other, source)) continue;
        // A shorter column cannot follow the longer one all the way down; it
        // stops at its own end rather than overscrolling into empty space.
        final target = source.pixels.clamp(
          other.minScrollExtent,
          other.maxScrollExtent,
        );
        if ((other.pixels - target).abs() > precisionErrorTolerance) {
          other.jumpTo(target);
        }
      }
    } finally {
      _mirroring = false;
    }
  }

  @override
  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    super.dispose();
  }
}
