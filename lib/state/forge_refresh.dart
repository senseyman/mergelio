import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_fetch.dart' show autoFetchDelay;
import 'forge.dart';
import 'settings.dart';
import 'settings_controller.dart';
import 'window_focus.dart';
import 'workspace.dart';

/// Shortest gap the scheduler will ever use, mirroring the settings floor.
const kMinForgeRefreshDelay = Duration(
  seconds: kMinForgeRefreshIntervalSeconds,
);

/// Whether a tick may run at all for the repository at [path]: it has to sit
/// on a supported forge, and a token has to be on file for it. Folding both
/// [forgeHostProvider] and [forgeTokenProvider] into one answer gives the
/// scheduler a single thing to watch rather than two it has to combine by
/// hand on every change.
final forgeRefreshEligibleProvider = FutureProvider.family<bool, String>((
  ref,
  path,
) async {
  final host = await ref.watch(forgeHostProvider(path).future);
  if (host == null) return false;
  final token = await ref.watch(forgeTokenProvider(path).future);
  return token != null;
});

/// Keeps the pull-request panel of the active repository current on a timer,
/// at the interval configured in settings.
///
/// A tick may only run while three things hold at once: a token is on file
/// for the active repository ([forgeRefreshEligibleProvider] folds this
/// together with the host check), the window has focus, and there is an
/// active tab at all. Losing any of them cancels the timer outright — with
/// no token, one tick spends up to 21 of the unauthenticated hourly budget
/// of 60, which is not something a background schedule may spend on its own.
///
/// Ticks are best-effort exactly like auto-fetch: one skipped for want of
/// focus is caught up when the window comes back, and a failing tick backs
/// the interval off via the same [autoFetchDelay] curve auto-fetch uses, so a
/// rate-limited or unreachable host is not retried at full rate.
class ForgeRefreshController {
  final Ref _ref;

  /// A fixed interval for tests; when null the interval is read live from
  /// settings so changing the preference reschedules the running timer.
  final Duration? _override;

  Timer? _timer;
  Duration? _interval;
  Duration? _base;
  int _failures = 0;
  bool _disposed = false;
  // Set when a tick is dropped for want of focus, so the window coming back
  // is known to have missed something.
  bool _missedTick = false;
  Future<void>? _inFlight;

  // The repository the scheduler is currently ticking for, and whether it is
  // currently allowed to. Both null/false while nothing is open or eligible.
  String? _path;
  bool _eligible = false;
  ProviderSubscription<AsyncValue<bool>>? _eligibilitySub;

  ForgeRefreshController(this._ref, {Duration? interval})
    : _override = interval {
    // A tab switch or a repo closing changes which repository (if any) the
    // scheduler tracks, and re-points the eligibility watch at it.
    _ref.listen<String?>(
      workspaceProvider.select((w) => w.activeTab?.path),
      (_, path) => _onPathChanged(path),
      fireImmediately: true,
    );
    // Reschedule whenever the interval changes.
    _ref.listen(
      settingsProvider.select((s) => s.forgeRefreshIntervalSeconds),
      (_, seconds) => _rescheduleInterval(seconds),
      fireImmediately: true,
    );
    // Coming back to a window that slept through a tick catches it up now
    // rather than leaving a stale panel until the next one falls due.
    _ref.listen<bool>(windowFocusedProvider, (previous, next) {
      if (next && previous == false) _onRegainedFocus();
    });
    _ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      _eligibilitySub?.close();
      _eligibilitySub = null;
    });
  }

  /// The gap before the next tick, or null while nothing is eligible to be
  /// ticked. Grows while ticks keep failing.
  @visibleForTesting
  Duration? get scheduledInterval => _timer == null ? null : _interval;

  /// The tick currently running, if any, so a test can await one that
  /// nothing else holds a handle to. Null before the first tick.
  @visibleForTesting
  Future<void>? get inFlightTick => _inFlight;

  void _onPathChanged(String? path) {
    if (path == _path) return;
    _path = path;
    _eligibilitySub?.close();
    _eligibilitySub = null;
    _setEligible(false);
    if (path == null) return;
    _eligibilitySub = _ref.listen<AsyncValue<bool>>(
      forgeRefreshEligibleProvider(path),
      (_, next) => _setEligible(next.valueOrNull ?? false),
      fireImmediately: true,
    );
  }

  void _setEligible(bool eligible) {
    if (_eligible == eligible) return;
    _eligible = eligible;
    // Becoming eligible (or losing it) is a fresh start, same as auto-fetch
    // treats a settings change: no backoff carried over, nothing owed from
    // before.
    _failures = 0;
    _missedTick = false;
    _armTimer();
  }

  void _rescheduleInterval(int seconds) {
    _failures = 0;
    _missedTick = false;
    // Floor a value stored by an older build, or one typed below the limit.
    final wanted = Duration(seconds: seconds);
    _base =
        _override ??
        (wanted < kMinForgeRefreshDelay ? kMinForgeRefreshDelay : wanted);
    if (_eligible) _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    final base = _base;
    if (!_eligible || base == null || _disposed || _path == null) {
      _timer = null;
      _interval = null;
      return;
    }
    _interval = autoFetchDelay(base, _failures);
    _timer = Timer(_interval!, () => _inFlight = tick());
  }

  void _onRegainedFocus() {
    if (_disposed || !_eligible || !_missedTick) return;
    _inFlight = tick();
  }

  /// One poll cycle: refresh unless the window is in the background, then
  /// arm the next timer with the delay that outcome earns. A backgrounded
  /// window leaves the tick owed, and regaining focus pays it.
  @visibleForTesting
  Future<void> tick() async {
    if (_disposed) return;
    final path = _path;
    try {
      if (path == null || !_eligible) {
        // A stray timer firing in the instant between eligibility going
        // false and the timer being cancelled. Nothing to do.
        return;
      }
      if (!_ref.read(windowFocusedProvider)) {
        // A skip is not a failure, so it neither grows nor resets the
        // backoff — it only earns a catch-up tick once the window returns.
        _missedTick = true;
      } else {
        _missedTick = false;
        _failures = await _refreshAndReport(path) ? 0 : _failures + 1;
      }
    } finally {
      // No-op once disposed, so a late tick cannot leave a live timer
      // behind.
      _armTimer();
    }
  }

  /// Invalidates the panel and waits for the reload it triggers, so the
  /// caller learns whether this tick actually landed. A skipped tick
  /// (nothing eligible, or the panel provider already mid-refresh) never
  /// reaches here.
  Future<bool> _refreshAndReport(String path) async {
    _ref.invalidate(pullRequestPanelProvider(path));
    try {
      await _ref.read(pullRequestPanelProvider(path).future);
      return true;
    } on Object {
      return false;
    }
  }

  /// Refreshes [path]'s panel right now, and — when it is the repository the
  /// scheduler is tracking — pushes the next scheduled tick a full interval
  /// out. A manual refresh, or one earned by a fetch/pull/push the user
  /// asked for, must not be followed seconds later by a scheduled tick that
  /// spends the same budget again for nothing.
  void refreshNow(String path) {
    _ref.invalidate(pullRequestPanelProvider(path));
    if (path != _path) return;
    _failures = 0;
    _missedTick = false;
    _armTimer();
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final forgeRefreshProvider = Provider<ForgeRefreshController>(
  (ref) => ForgeRefreshController(ref),
);
