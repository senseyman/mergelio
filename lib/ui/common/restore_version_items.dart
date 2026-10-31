import 'package:flutter/material.dart';

import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';

/// A file as one commit holds it: what a restore reads from.
typedef RestoreSource = ({String rev, String path});

/// The versions of [f] a commit's file list can put back in the working
/// tree: the one [sha] left, and the one its first parent had. Each is null
/// where the file did not exist — a file the commit deleted has no version
/// in it, and one it added or copied has none before it. A rename's earlier
/// version lives under its old name.
typedef RestoreSources = ({
  RestoreSource? thisVersion,
  RestoreSource? parentVersion,
});

RestoreSources restoreVersionSources(
  String sha,
  List<String> parents,
  CommitFileChange f,
) => (
  thisVersion: f.change == GitChange.deleted ? null : (rev: sha, path: f.path),
  parentVersion:
      parents.isEmpty ||
          f.change == GitChange.added ||
          f.change == GitChange.copied
      ? null
      : (rev: parents.first, path: f.origPath ?? f.path),
);

/// Context-menu entries restoring [f] as commit [sha] left it, or as it was
/// before. Nothing is staged; the user reviews and commits.
List<PopupMenuEntry<void>> restoreVersionMenuItems({
  required BuildContext context,
  required RepoActions actions,
  required String sha,
  required List<String> parents,
  required CommitFileChange f,
}) {
  final l = AppLocalizations.of(context);
  const style = TextStyle(fontSize: 13);
  final s = restoreVersionSources(sha, parents, f);
  PopupMenuItem<void> item(RestoreSource src, String label) => PopupMenuItem(
    height: 34,
    onTap: () => actions.restoreFileVersion(src.rev, src.path),
    child: Text(label, style: style),
  );
  return [
    if (s.thisVersion case final src?) item(src, l.rfvRestoreThisVersion),
    if (s.parentVersion case final src?) item(src, l.rfvRestoreParentVersion),
  ];
}
