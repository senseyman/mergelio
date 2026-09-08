import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the app window currently has focus. Defaults to true so tests and
/// any platform that never reports a focus event behave as if it does.
final windowFocusedProvider = StateProvider<bool>((_) => true);

/// Mirrors the native window's focus state into [windowFocusedProvider].
/// Background polling (auto-fetch) reads it: a hidden or minimised window has
/// nobody watching the graph, so talking to every remote on a timer there buys
/// nothing and spends the host's rate limit.
class WindowFocusTracker with WindowListener {
  final void Function(bool focused) onChanged;

  WindowFocusTracker(this.onChanged);

  @override
  void onWindowFocus() => onChanged(true);

  @override
  void onWindowBlur() => onChanged(false);

  @override
  void onWindowMinimize() => onChanged(false);

  @override
  void onWindowRestore() => onChanged(true);
}

/// Instantiate once (watched by the app shell) to keep the tracker registered
/// for the app's lifetime.
final windowFocusSyncProvider = Provider<WindowFocusTracker>((ref) {
  final tracker = WindowFocusTracker(
    (focused) => ref.read(windowFocusedProvider.notifier).state = focused,
  );
  windowManager.addListener(tracker);
  ref.onDispose(() => windowManager.removeListener(tracker));
  return tracker;
});
