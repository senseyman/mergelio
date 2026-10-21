import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/repo_actions.dart';

/// Context-menu entries that hand [path] to a program outside Mergelio: the
/// user's editor, at [line], and — when [diff] is given — git's diff tool.
/// The editor always gets the working-tree copy, whatever [diff] shows.
List<PopupMenuEntry<void>> externalToolMenuItems({
  required BuildContext context,
  required RepoActions actions,
  required String path,
  DiffTarget? diff,
  int line = 1,
}) {
  final l = AppLocalizations.of(context);
  const style = TextStyle(fontSize: 13);
  return [
    PopupMenuItem(
      height: 34,
      onTap: () => actions.openInEditor(path, line: line),
      child: Text(l.extOpenInEditor, style: style),
    ),
    if (diff != null)
      PopupMenuItem(
        height: 34,
        onTap: () => actions.openDifftool(diff),
        child: Text(l.extOpenInDiffTool, style: style),
      ),
  ];
}
