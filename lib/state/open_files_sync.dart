import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_files.dart';
import 'workspace.dart';

/// Keeps the editor tabs of every open repository and the persisted workspace
/// in step: a restored tab hands its files to the editors, and every open or
/// close is written back so a restart reopens the same set.
///
/// Lives outside the widgets because it has to keep working while Files mode
/// is not on screen — a repository left in graph mode still remembers what it
/// had open.
class OpenFilesSync {
  final Ref _ref;

  /// Repositories whose write-back is already subscribed, so a rebuilt tab
  /// list does not stack duplicate listeners.
  final _wired = <String>{};

  OpenFilesSync(this._ref) {
    _ref.listen(
      workspaceProvider.select((w) => w.tabs),
      (_, tabs) => _wire(tabs),
    );
    // A provider may not touch other providers while it is being built, so
    // the tabs already open when the app starts are picked up a microtask
    // later rather than in the constructor.
    Future.microtask(() => _wire(_ref.read(workspaceProvider).tabs));
  }

  void _wire(List<RepoTab> tabs) {
    for (final tab in tabs) {
      // The persisted set arrives after the tab itself does — a restored
      // session opens the tab first, then fills it in. Handing it over
      // whenever the editors are empty covers both orders, and closing every
      // editor writes the empty set back, so nothing is ever re-restored over
      // a deliberate close.
      if (tab.openFiles.isNotEmpty &&
          _ref.read(openFilesProvider(tab.path)).paths.isEmpty) {
        _ref
            .read(openFilesProvider(tab.path).notifier)
            .restore(tab.openFiles, active: tab.activeFile);
      }
      if (!_wired.add(tab.path)) continue;
      final path = tab.path;
      _ref.listen(openFilesProvider(path), (_, open) {
        _ref
            .read(workspaceProvider.notifier)
            .setOpenFiles(path, open.paths, open.active);
      });
    }
    // A repository that was closed may be reopened later, and should restore
    // from what was persisted rather than from a stale wiring.
    _wired.removeWhere((path) => !tabs.any((t) => t.path == path));
  }
}

/// Kept alive by the app shell for the app's lifetime.
final openFilesSyncProvider = Provider<OpenFilesSync>(OpenFilesSync.new);
