import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'operation_journal.dart';
import 'profiles.dart';
import 'workspace.dart';

/// Per-profile workspaces: each profile owns its own set of groups and open
/// repos. Switching the active profile loads that profile's saved workspace, so
/// you only ever see the groups/repos created under the current profile.
class ProfileWorkspaceSync {
  final Ref _ref;
  String? _lastId;

  ProfileWorkspaceSync(this._ref) {
    _lastId = _ref.read(profilesProvider).activeId;
    _ref.listen(profilesProvider.select((s) => s.activeId), (prev, next) {
      if (next == null || next == _lastId) return;
      _lastId = next;
      _switch(next);
    });
  }

  Future<void> _switch(String profileId) async {
    final store = _ref.read(kvStoreProvider);
    final ws = _ref.read(workspaceProvider.notifier);
    try {
      final session = await WorkspaceController.restoreSessionFor(
        store,
        profileId,
      );
      ws.useProfile(profileId, session);
    } on Object catch (e) {
      debugPrint('profile workspace sync failed: $e');
    }
  }
}

/// Kept alive by the app shell.
final profileWorkspaceSyncProvider = Provider<ProfileWorkspaceSync>(
  ProfileWorkspaceSync.new,
);
