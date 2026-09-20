import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'window_focus.dart';

/// Shared machinery behind [AutoFetchController] and [ForgeRefreshController]:
/// a timer that fires at a configurable interval, skips a tick while the
/// window is unfocused, catches that missed tick up once focus returns, and
/// backs its own interval off on repeated failure.
///
/// A subclass supplies what a tick actually does ([runTick]), and narrows how
/// much beyond "there is a base interval and this is not disposed" gates
/// arming ([canArm]) or a regained-focus catch-up ([isActive]). Everything
/// about the timer itself — arming, the focus-skip/catch-up dance, the
/// failure backoff, and making sure nothing a tick does can escape as an
/// unhandled error — lives here once, so a fix to one applies to both.
abstract class PollingScheduler {
  final Ref ref;

  /// A fixed interval for tests; when null the interval is read live from
  /// settings so changing the preference reschedules the running timer.
  final Duration? overrideInterval;

  Timer? _timer;
  Duration? _interval;
  Duration? _base;
  int _failures = 0;
  bool _disposed = false;
  // Set when a tick is dropped for want of focus, so the window coming back
  // is known to have missed something.
  bool _missedTick = false;
  Future<void>? _inFlight;

  PollingScheduler(this.ref, {Duration? interval})
    : overrideInterval = interval {
    // Coming back to a window that slept through a tick catches it up now
    // rather than leaving stale data until the next one falls due.
    ref.listen<bool>(windowFocusedProvider, (previous, next) {
      if (next && previous == false) _onRegainedFocus();
    });
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      disposeExtra();
    });
  }

  /// Whether the timer may be armed right now, beyond having a base interval
  /// and not being disposed. Default true; a subclass with extra eligibility
  /// (a token on file, a repository open) narrows this further.
  @protected
  bool get canArm => true;

  /// Whether a regained-focus catch-up tick should run right now.
  @protected
  bool get isActive;

  /// Extra teardown a subclass needs when the controller is disposed.
  @protected
  void disposeExtra() {}

  /// Prefix for the tick-failure debug log line.
  @protected
  String get logLabel;

  /// Whether the tick about to run should do anything beyond rearming the
  /// next one. False is a no-op tick — it still rearms, nothing else. Only
  /// needed by a scheduler whose eligibility can flip in the instant between
  /// a timer firing and it being cancelled.
  @protected
  bool readyForTick() => true;

  /// Runs the one thing this tick does while the window has focus. Returns
  /// whether it succeeded, which drives the failure backoff. Anything this
  /// throws is caught by [tick] and counted as a failure — it never needs to
  /// catch its own errors.
  @protected
  Future<bool> runTick();

  /// The gap [base] and [failures] earn right now. Both controllers back off
  /// the same way; see `autoFetchDelay`.
  @protected
  Duration backoffFor(Duration base, int failures);

  /// The gap before the next tick, or null while nothing is scheduled. Grows
  /// while ticks keep failing.
  @visibleForTesting
  Duration? get scheduledInterval => _timer == null ? null : _interval;

  /// The tick currently running, if any, so a test can await one that
  /// nothing else holds a handle to. Null before the first tick.
  @visibleForTesting
  Future<void>? get inFlightTick => _inFlight;

  /// The configured base interval; null while ticking is off.
  @protected
  Duration? get base => _base;

  /// Replaces the configured base interval; null turns ticking off.
  @protected
  set base(Duration? value) => _base = value;

  /// Resets the failure backoff and the missed-tick flag together — the
  /// fresh start a settings change, or a gained/lost eligibility, earns in
  /// both controllers.
  @protected
  void resetBackoff() {
    _failures = 0;
    _missedTick = false;
  }

  @protected
  void armTimer() => _armTimer();

  void _onRegainedFocus() {
    // Nothing to catch up on unless this is active and a tick was dropped.
    if (_disposed || !isActive || !_missedTick) return;
    _inFlight = tick();
  }

  void _armTimer() {
    _timer?.cancel();
    final base = _base;
    // A tick can outlive the container it reads from; arming again here
    // would leave a timer nobody cancels.
    if (base == null || _disposed || !canArm) {
      _timer = null;
      _interval = null;
      return;
    }
    _interval = backoffFor(base, _failures);
    _timer = Timer(_interval!, () => _inFlight = tick());
  }

  /// One poll cycle: run [runTick] unless the window is in the background,
  /// then arm the next timer with the delay that outcome earns. A
  /// backgrounded window leaves the tick owed, and regaining focus pays it.
  @visibleForTesting
  Future<void> tick() async {
    if (_disposed) return;
    try {
      if (!readyForTick()) return;
      if (!ref.read(windowFocusedProvider)) {
        // A skip is not a failure, so it neither grows nor resets the
        // backoff — it only earns a catch-up tick once the window returns.
        _missedTick = true;
      } else {
        _missedTick = false;
        try {
          _failures = await runTick() ? 0 : _failures + 1;
        } on Object catch (e) {
          // tick() runs unawaited from a Timer callback in production;
          // letting this escape would surface as an unhandled async error
          // and take the scheduler down instead of just backing off.
          debugPrint('$logLabel tick failed: $e');
          _failures++;
        }
      }
    } finally {
      // No-op once disposed, so a late tick cannot leave a live timer
      // behind.
      _armTimer();
    }
  }
}
