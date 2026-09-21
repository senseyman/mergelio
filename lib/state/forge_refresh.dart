import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_fetch.dart' show autoFetchDelay;
import 'forge.dart';
import 'polling_scheduler.dart';
import 'settings.dart';
import 'settings_controller.dart';
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
class ForgeRefreshController extends PollingScheduler {
  // The repository the scheduler is currently ticking for, and whether it is
  // currently allowed to. Both null/false while nothing is open or eligible.
  String? _path;
  bool _eligible = false;
  ProviderSubscription<AsyncValue<bool>>? _eligibilitySub;

  ForgeRefreshController(super.ref, {super.interval}) {
    // A tab switch or a repo closing changes which repository (if any) the
    // scheduler tracks, and re-points the eligibility watch at it.
    ref.listen<String?>(
      workspaceProvider.select((w) => w.activeTab?.path),
      (_, path) => _onPathChanged(path),
      fireImmediately: true,
    );
    // Reschedule whenever the interval changes.
    ref.listen(
      settingsProvider.select((s) => s.forgeRefreshIntervalSeconds),
      (_, seconds) => _rescheduleInterval(seconds),
      fireImmediately: true,
    );
  }

  @override
  void disposeExtra() {
    _eligibilitySub?.close();
    _eligibilitySub = null;
  }

  @override
  bool get isActive => _eligible;

  @override
  bool get canArm => _eligible && _path != null;

  @override
  String get logLabel => 'forge-refresh';

  @override
  Duration backoffFor(Duration base, int failures) =>
      autoFetchDelay(base, failures);

  @override
  bool readyForTick() => _path != null && _eligible;

  @override
  Future<bool> runTick() => _refreshAndReport(_path!);

  void _onPathChanged(String? path) {
    if (path == _path) return;
    _path = path;
    _eligibilitySub?.close();
    _eligibilitySub = null;
    _setEligible(false);
    if (path == null) return;
    _eligibilitySub = ref.listen<AsyncValue<bool>>(
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
    resetBackoff();
    armTimer();
  }

  void _rescheduleInterval(int seconds) {
    resetBackoff();
    // Floor a value stored by an older build, or one typed below the limit.
    final wanted = Duration(seconds: seconds);
    base =
        overrideInterval ??
        (wanted < kMinForgeRefreshDelay ? kMinForgeRefreshDelay : wanted);
    if (_eligible) armTimer();
  }

  /// Invalidates both panels and waits for the reload each triggers, so the
  /// caller learns whether this tick actually landed. A skipped tick
  /// (nothing eligible, or a panel provider already mid-refresh) never
  /// reaches here. Anything either step throws propagates to [tick], which
  /// counts it as a failure rather than letting it escape unhandled.
  Future<bool> _refreshAndReport(String path) async {
    ref.invalidate(pullRequestPanelProvider(path));
    ref.invalidate(issuePanelProvider(path));
    await ref.read(pullRequestPanelProvider(path).future);
    await ref.read(issuePanelProvider(path).future);
    return true;
  }

  /// Refreshes [path]'s panels right now, and — when it is the repository
  /// the scheduler is tracking — pushes the next scheduled tick a full
  /// interval out. A manual refresh, or one earned by a fetch/pull/push the
  /// user asked for, must not be followed seconds later by a scheduled tick
  /// that spends the same budget again for nothing.
  ///
  /// Refreshes because a person asked for these rows.
  ///
  /// Deliberately ungated: pressing refresh IS the request, and refusing it
  /// for want of a token would leave a control that silently does nothing.
  /// The budget is guarded where spending is incidental instead — the timer,
  /// and the git operations that refresh as a side effect.
  void refreshNow(String path) {
    ref.invalidate(pullRequestPanelProvider(path));
    ref.invalidate(issuePanelProvider(path));
    _bumpSchedule(path);
  }

  /// Refreshes because a git operation happened to touch the remote.
  ///
  /// The person asked to fetch, pull or push — not to spend a further
  /// budget's worth of requests on forge data. The two halves cost too
  /// differently to gate alike: issues are a single request, noise beside
  /// even the 60 an hour an anonymous caller gets, so they always refresh.
  /// Pull requests carry two check lookups per row, and spending a third of
  /// that hourly budget on every fetch would be the kind of background cost
  /// nobody agreed to — so that half waits for a token.
  void refreshAfterGitOp(String path) {
    ref.invalidate(issuePanelProvider(path));
    if (ref.read(forgeTokenProvider(path)).valueOrNull != null) {
      ref.invalidate(pullRequestPanelProvider(path));
    }
    _bumpSchedule(path);
  }

  /// Pushes the next scheduled tick a full interval out, so a refresh that
  /// just happened is not repeated seconds later by the timer. Only the
  /// tracked repository has a timer to push.
  void _bumpSchedule(String path) {
    if (path != _path) return;
    resetBackoff();
    armTimer();
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final forgeRefreshProvider = Provider<ForgeRefreshController>(
  (ref) => ForgeRefreshController(ref),
);
