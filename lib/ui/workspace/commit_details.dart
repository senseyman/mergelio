import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/diff_target.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../graph/commit_columns.dart';

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
                if (c.signed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 13,
                          color: t.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Signed',
                          style: TextStyle(color: t.success, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'CHANGED FILES',
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
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
                  data: (list) => list.isEmpty
                      ? Text(
                          'No changes',
                          style: TextStyle(color: t.textFaint, fontSize: 12),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final f in list)
                              _FileRow(
                                file: f,
                                onTap: () =>
                                    ref
                                        .read(diffTargetProvider.notifier)
                                        .state = DiffTarget(
                                      repoPath: repoPath,
                                      path: f.path,
                                      commitSha: c.sha,
                                    ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
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
  final VoidCallback onTap;
  const _FileRow({required this.file, required this.onTap});

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
    return InkWell(
      onTap: onTap,
      hoverColor: t.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
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
                file.origPath == null
                    ? file.path
                    : '${file.origPath} → ${file.path}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
