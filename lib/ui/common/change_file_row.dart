import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../insight/file_insight_dialog.dart';
import 'dialogs.dart';

/// One row of a changed-file list: status badge, path, and the history/blame
/// context menu. Shared by every read-only file list — a commit's changes and
/// a comparison of two revisions.
class ChangeFileRow extends StatelessWidget {
  final CommitFileChange file;
  final String repoPath;
  final VoidCallback onTap;
  final double indent;
  final bool inTree;
  const ChangeFileRow({
    super.key,
    required this.file,
    required this.repoPath,
    required this.onTap,
    this.indent = 0,
    this.inTree = false,
  });

  String get _label {
    if (inTree) {
      final i = file.path.lastIndexOf('/');
      return i < 0 ? file.path : file.path.substring(i + 1);
    }
    return file.origPath == null
        ? file.path
        : '${file.origPath} → ${file.path}';
  }

  void _menu(BuildContext context, Offset at) {
    final l = AppLocalizations.of(context);
    showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () =>
              showFileInsight(context, repoPath: repoPath, path: file.path),
          child: Text(l.wtpFileHistory, style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          height: 34,
          onTap: () => showFileInsight(
            context,
            repoPath: repoPath,
            path: file.path,
            initialTab: 1,
          ),
          child: Text(l.wtpBlame, style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, letter) = switch (file.change) {
      GitChange.added => (t.success, 'A'),
      GitChange.deleted => (t.danger, 'D'),
      GitChange.renamed => (t.accent, 'R'),
      GitChange.copied => (t.accent, 'C'),
      _ => (t.warning, 'M'),
    };
    return GestureDetector(
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: t.hover,
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent, 3, 0, 3),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
