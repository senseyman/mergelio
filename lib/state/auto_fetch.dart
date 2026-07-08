import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'repo_actions.dart';
import 'settings_controller.dart';
import 'workspace.dart';

/// Periodically fetches the active repository while the "Auto-fetch" preference
/// is on. Ticks are best-effort: they skip when no repo is open or it has no
/// remote, and [RepoActions.fetch] itself no-ops while another network op runs.
class AutoFetchController {
  final Ref _ref;
  final Duration interval;
  Timer? _timer;

  AutoFetchController(this._ref, {this.interval = const Duration(minutes: 3)}) {
    _ref.listen(
      settingsProvider.select((s) => s.autoFetch),
      (_, on) => _reschedule(on),
      fireImmediately: true,
    );
    _ref.onDispose(() => _timer?.cancel());
  }

  void _reschedule(bool on) {
    _timer?.cancel();
    _timer = on ? Timer.periodic(interval, (_) => fetchNow()) : null;
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
    await _ref.read(repoActionsProvider(tab.path)).fetch();
  }
}

/// Instantiate once (e.g. watched by the app shell) to keep it alive.
final autoFetchProvider = Provider<AutoFetchController>(
  (ref) => AutoFetchController(ref),
);
