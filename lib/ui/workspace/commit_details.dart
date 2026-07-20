import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/diff_target.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../common/file_tree_view.dart';
import '../graph/commit_columns.dart';
import '../graph/ref_pill.dart';
import '../insight/file_insight_dialog.dart';

/// Right panel content for a selected commit: metadata, signature, the list of
/// changed files (read-only), and a `‹ WIP` shortcut back to the working tree
/// when it is dirty.
class CommitDetails extends ConsumerWidget {
  final String repoPath;
  final Commit commit;
  final bool hasWip;
  const CommitDetails({
    super.key,
    required this.repoPath,
    required this.commit,
    required this.hasWip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final c = commit;
    final files = ref.watch(commitFilesProvider((repo: repoPath, sha: c.sha)));

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Text(
                  'COMMIT',
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (hasWip)
                  TextButton(
                    onPressed: () =>
                        ref.read(selectedCommitProvider.notifier).state =
                            wipSelection,
                    child: const Text('‹ WIP', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  c.message,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (c.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    c.body,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
                if (c.refs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final r in c.refs) RefPill(gitRef: r)],
                  ),
                ],
                const SizedBox(height: 12),
                _Meta(label: 'Author', value: '${c.author} <${c.authorEmail}>'),
                _Meta(label: 'Date', value: formatCommitDate(c.date)),
                _MetaSha(sha: c.sha),
                for (final p in c.parents)
                  _Meta(
                    label: 'Parent',
                    value: p.length > 7 ? p.substring(0, 7) : p,
                    mono: true,
                  ),
                if (c.signed) _Signature(status: c.sigStatus),
                if (c.coauthor)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.group_outlined, size: 13, color: t.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Co-authored',
                          style: TextStyle(color: t.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'CHANGED FILES',
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    const FileViewToggle(),
                  ],
                ),
                const SizedBox(height: 6),
                files.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    'Could not read changes',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Text(
                        'No changes',
                        style: TextStyle(color: t.textFaint, fontSize: 12),
                      );
                    }
                    final tree = ref.watch(
                      settingsProvider.select((s) => s.filesAsTree),
                    );
                    final byPath = {for (final f in list) f.path: f};
                    return FileTreeView(
                      paths: [for (final f in list) f.path],
                      tree: tree,
                      fileRow: (path, depth) => _FileRow(
                        file: byPath[path]!,
                        repoPath: repoPath,
                        indent: FileTreeView.indent(depth),
                        inTree: tree,
                        onTap: () =>
                            ref
                                .read(diffTargetProvider.notifier)
                                .state = DiffTarget(
                              repoPath: repoPath,
                              path: path,
                              commitSha: c.sha,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Signature indicator whose wording matches the real `%G?` status — never
/// claims "Verified" for a bad, expired or revoked signature.
class _Signature extends StatelessWidget {
  final String status;
  const _Signature({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (label, color, icon) = switch (status) {
      // 'G' is a good, trusted signature; 'U' is good but the key's validity is
      // unknown/untrusted — never assert "verified" for it.
      'G' => ('Verified signature', t.success, Icons.verified_user_outlined),
      'U' => ('Valid, untrusted key', t.warning, Icons.gpp_maybe_outlined),
      'X' || 'Y' => ('Expired signature', t.warning, Icons.gpp_maybe_outlined),
      'R' => ('Revoked key', t.danger, Icons.gpp_bad_outlined),
      'B' => ('Bad signature', t.danger, Icons.gpp_bad_outlined),
      _ => ('Signed', t.textMuted, Icons.lock_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _Meta({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: t.textMuted,
                fontSize: 11.5,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaSha extends StatelessWidget {
  final String sha;
  const _MetaSha({required this.sha});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final short = sha.length > 7 ? sha.substring(0, 7) : sha;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              'SHA',
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
          Text(
            short,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: sha)),
            child: Icon(Icons.copy_outlined, size: 12, color: t.textFaint),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final CommitFileChange file;
  final String repoPath;
  final VoidCallback onTap;
  final double indent;
  final bool inTree;
  const _FileRow({
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
    showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () =>
              showFileInsight(context, repoPath: repoPath, path: file.path),
          child: const Text('File history', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          height: 34,
          onTap: () => showFileInsight(
            context,
            repoPath: repoPath,
            path: file.path,
            initialTab: 1,
          ),
          child: const Text('Blame', style: TextStyle(fontSize: 13)),
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
