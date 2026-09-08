import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'repo_actions.dart';
import 'settings.dart';
import 'settings_controller.dart';
import 'window_focus.dart';
import 'workspace.dart';

/// Shortest gap the scheduler will ever use, mirroring the settings floor.
const kMinAutoFetchDelay = Duration(seconds: kMinAutoFetchIntervalSeconds);

/// Ceiling for the failure backoff. A dead remote or a dropped network stops
/// costing anything once ticks are half an hour apart, and the next successful
/// tick puts the interval straight back to what the user configured.
const kMaxAutoFetchDelay = Duration(minutes: 30);

/// Gap before the next tick: the configured [base], doubled once per
/// consecutive failure. The cap never shortens a base the user chose longer.
Duration autoFetchDelay(Duration base, int consecutiveFailures) {
  if (consecutiveFailures <= 0) return base;
  // 2^n, with n bounded so the shift cannot run away on a long outage.
  final backedOff = base * (1 << consecutiveFailures.clamp(1, 20));
  if (backedOff <= kMaxAutoFetchDelay) return backedOff;
  return base > kMaxAutoFetchDelay ? base : kMaxAutoFetchDelay;
}

/// Periodically fetches the active repository while the "Auto-fetch"
/// preference is on, at the interval configured in settings. Ticks are
/// best-effort: they skip when the window is unfocused — the fetch they missed
/// runs when it comes back — when no repo is open
/// or it has no remote, and [RepoActions.fetch] itself no-ops while another
/// fetch is still running. A tick never blocks the user: it holds the fetch
/// lane only, so a commit, a branch create or a push goes through while it is
/// in flight. Failures back the timer off so a dead remote is not retried at
/// full rate.
class AutoFetchController {
  final Ref _ref;

  /// A fixed interval for tests; when null the interval is read live from
  /// settings so changing the preference reschedules the running timer.
  final Duration? _override;

  Timer? _timer;
  Duration? _interval;
  Duration? _base;
  int _failures = 0;
  bool _disposed = false;
  // Set when a tick is dropped for want of focus, so the window coming back is
  // known to have missed something.
  bool _missedTick = false;
  Future<void>? _inFlight;

  AutoFetchController(this._ref, {Duration? interval}) : _override = interval {
    // Reschedule whenever the toggle or the interval changes.
    _ref.listen(
      settingsProvider.select((s) => (s.autoFetch, s.autoFetchIntervalSeconds)),
      (_, next) => _reschedule(on: next.$1, seconds: next.$2),
      fireImmediately: true,
    );
    // Coming back to a window that slept through a tick catches it up now
    // rather than leaving a stale graph until the next one falls due.
    _ref.listen<bool>(windowFocusedProvider, (previous, next) {
      if (next && previous == false) _onRegainedFocus();
    });
    _ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
  }

  /// The gap before the next tick, or null while auto-fetch is off. Grows
  /// while fetches keep failing.
  @visibleForTesting
  Duration? get scheduledInterval => _timer == null ? null : _interval;

  /// The tick currently running, if any, so a test can await one that nothing
  /// else holds a handle to. Null before the first tick.
  @visibleForTesting
  Future<void>? get inFlightTick => _inFlight;

  void _onRegainedFocus() {
    // Nothing to catch up on unless auto-fetch is on and a tick was dropped.
    if (_disposed || _base == null || !_missedTick) return;
    _inFlight = tick();
  }

  void _reschedule({required bool on, required int seconds}) {
    _timer?.cancel();
    if (!on) {
      _timer = null;
      _interval = null;
      _base = null;
      _failures = 0;
      return;
    }
    // A settings change is a fresh start: honour the new interval at once
    // instead of serving out a backoff earned under the old one, and without
    // owing a catch-up for a tick missed under it.
    _failures = 0;
    _missedTick = false;
    // Floor a value stored by an older build, which offered shorter periods.
    final wanted = Duration(seconds: seconds);
    _base =
        _override ??
        (wanted < kMinAutoFetchDelay ? kMinAutoFetchDelay : wanted);
    _armTimer();
  }

  void _armTimer() {
    _timer?.cancel();
    final base = _base;
    // A tick can outlive the container it reads from; arming again here would
    // leave a timer nobody cancels.
    if (base == null || _disposed) {
      _timer = null;
      _interval = null;
      return;
    }
    _interval = autoFetchDelay(base, _failures);
    _timer = Timer(_interval!, () => _inFlight = tick());
  }

  /// One poll cycle: fetch unless the window is in the background, then arm
  /// the next timer with the delay that outcome earns. A backgrounded window
  /// leaves the tick owed, and regaining focus pays it.
  @visibleForTesting
  Future<void> tick() async {
    if (_disposed) return;
    try {
      if (!_ref.read(windowFocusedProvider)) {
        // A skip is not a failure, so it neither grows nor resets the backoff —
        // it only earns a catch-up fetch when the window comes back.
        _missedTick = true;
      } else {
        _missedTick = false;
        _failures = await fetchNow() ? 0 : _failures + 1;
      }
    } on Object catch (e) {
      // A repo that moved or vanished makes even reading the remotes throw.
      // Nothing here may escape: this future is unawaited, and a tick that
      // died before rearming would end auto-fetch for the rest of the session.
      debugPrint('auto-fetch: tick failed ($e)');
      _failures++;
    } finally {
      // No-op once disposed, so a late tick cannot leave a live timer behind.
      _armTimer();
    }
  }

  /// Fetches the active repo now, if it exists and has a remote. Returns false
  /// only when a fetch actually ran and failed; a skipped tick reports true so
  /// it does not trigger the backoff.
  Future<bool> fetchNow() async {
    final tab = _ref.read(workspaceProvider).activeTab;
    if (tab == null) return true;
    final remotes = await GitReader(
      _ref.read(gitServiceProvider),
      tab.path,
    ).remotes();
    if (remotes.isEmpty) return true;
    // Background tick: stay silent so only manual fetches toast.
    return _ref.read(repoActionsProvider(tab.path)).fetch(silent: true);
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final autoFetchProvider = Provider<AutoFetchController>(
  (ref) => AutoFetchController(ref),
);
