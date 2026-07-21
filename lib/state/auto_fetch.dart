import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'repo_actions.dart';
import 'settings_controller.dart';
import 'workspace.dart';

/// Periodically fetches the active repository while the "Auto-fetch" preference
/// is on, at the interval configured in settings. Ticks are best-effort: they
/// skip when no repo is open or it has no remote, and [RepoActions.fetch]
/// itself no-ops while another network op runs.
class AutoFetchController {
  final Ref _ref;

  /// A fixed interval for tests; when null the interval is read live from
  /// settings so changing the preference reschedules the running timer.
  final Duration? _override;

  Timer? _timer;
  Duration? _interval;

  AutoFetchController(this._ref, {Duration? interval}) : _override = interval {
    // Reschedule whenever the toggle or the interval changes.
    _ref.listen(
      settingsProvider.select((s) => (s.autoFetch, s.autoFetchIntervalSeconds)),
      (_, next) => _reschedule(on: next.$1, seconds: next.$2),
      fireImmediately: true,
    );
    _ref.onDispose(() => _timer?.cancel());
  }

  /// The interval of the currently running timer, or null while auto-fetch is
  /// off.
  @visibleForTesting
  Duration? get scheduledInterval => _timer == null ? null : _interval;

  void _reschedule({required bool on, required int seconds}) {
    _timer?.cancel();
    if (!on) {
      _timer = null;
      _interval = null;
      return;
    }
    _interval = _override ?? Duration(seconds: seconds);
    _timer = Timer.periodic(_interval!, (_) => fetchNow());
  }

  /// Fetches the active repo now, if it exists and has a remote.
  Future<void> fetchNow() async {
    final tab = _ref.read(workspaceProvider).activeTab;
    if (tab == null) return;
    final remotes = await GitReader(
      _ref.read(gitServiceProvider),
      tab.path,
    ).remotes();
    if (remotes.isEmpty) return;
    // Background tick: stay silent so only manual fetches toast.
    await _ref.read(repoActionsProvider(tab.path)).fetch(silent: true);
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final autoFetchProvider = Provider<AutoFetchController>(
  (ref) => AutoFetchController(ref),
);
