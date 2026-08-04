import 'git/models.dart';
import 'project_status.dart';

/// What the navigator's context menu can offer for one row.
enum ProjectMenuItem {
  newFile,
  newFolder,
  rename,
  delete,
  stage,
  unstage,
  discard,
  history,
  reveal,
}

/// The items [status] and [change] earn for one row, in menu order. Pure: the
/// menu renders this list rather than deciding what to show while building.
///
/// [change] is the working-tree entry git reports for the row, when there is
/// one. Everything that exists on disk can be renamed, deleted and revealed;
/// the git items appear only where they mean something.
List<ProjectMenuItem> projectMenuItems({
  required bool isDir,
  required EntryStatus status,
  WorkingFile? change,
}) => [
  if (isDir) ...[ProjectMenuItem.newFile, ProjectMenuItem.newFolder],
  ProjectMenuItem.rename,
  ProjectMenuItem.delete,
  if (!isDir) ...[
    if (change?.isUnstaged ?? false) ProjectMenuItem.stage,
    if (change?.isStaged ?? false) ProjectMenuItem.unstage,
    if (change != null) ProjectMenuItem.discard,
    // Git records history for files it tracks; an untracked file has none,
    // and an unknown one is a failed read rather than an answer.
    if (status == EntryStatus.clean || status == EntryStatus.modified)
      ProjectMenuItem.history,
  ],
  ProjectMenuItem.reveal,
];

/// The items offered where there is no row — the navigator's empty space,
/// which stands for the project root. Only what needs no selection: creating,
/// and opening the project in the file manager.
List<ProjectMenuItem> projectRootMenuItems() => const [
  ProjectMenuItem.newFile,
  ProjectMenuItem.newFolder,
  ProjectMenuItem.reveal,
];
