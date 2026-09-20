import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'polling_scheduler.dart';
import 'repo_actions.dart';
import 'settings.dart';
import 'settings_controller.dart';
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
class AutoFetchController extends PollingScheduler {
  AutoFetchController(super.ref, {super.interval}) {
    // Reschedule whenever the toggle or the interval changes.
    ref.listen(
      settingsProvider.select((s) => (s.autoFetch, s.autoFetchIntervalSeconds)),
      (_, next) => _reschedule(on: next.$1, seconds: next.$2),
      fireImmediately: true,
    );
  }

  // Ticking is active exactly when a base interval is configured, i.e. while
  // the "Auto-fetch" preference is on.
  @override
  bool get isActive => base != null;

  @override
  String get logLabel => 'auto-fetch';

  @override
  Duration backoffFor(Duration base, int failures) =>
      autoFetchDelay(base, failures);

  @override
  Future<bool> runTick() => fetchNow();

  void _reschedule({required bool on, required int seconds}) {
    if (!on) {
      base = null;
      resetBackoff();
      armTimer();
      return;
    }
    // A settings change is a fresh start: honour the new interval at once
    // instead of serving out a backoff earned under the old one, and without
    // owing a catch-up for a tick missed under it.
    resetBackoff();
    // Floor a value stored by an older build, which offered shorter periods.
    final wanted = Duration(seconds: seconds);
    base =
        overrideInterval ??
        (wanted < kMinAutoFetchDelay ? kMinAutoFetchDelay : wanted);
    armTimer();
  }

  /// Fetches the active repo now, if it exists and has a remote. Returns false
  /// only when a fetch actually ran and failed; a skipped tick reports true so
  /// it does not trigger the backoff.
  Future<bool> fetchNow() async {
    final tab = ref.read(workspaceProvider).activeTab;
    if (tab == null) return true;
    final remotes = await GitReader(
      ref.read(gitServiceProvider),
      tab.path,
    ).remotes();
    if (remotes.isEmpty) return true;
    // Background tick: stay silent so only manual fetches toast.
    return ref.read(repoActionsProvider(tab.path)).fetch(silent: true);
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final autoFetchProvider = Provider<AutoFetchController>(
  (ref) => AutoFetchController(ref),
);
