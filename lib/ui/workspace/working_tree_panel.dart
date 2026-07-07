import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';

/// Right panel shown when no commit is selected: STAGED / UNSTAGED file lists
/// and the commit composer. A partially-staged file appears in both lists.
class WorkingTreePanel extends ConsumerWidget {
  final String repoPath;
  final RepoData data;
  const WorkingTreePanel({
    super.key,
    required this.repoPath,
    required this.data,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final actions = ref.read(repoActionsProvider(repoPath));
    final staged = data.working.where((f) => f.isStaged).toList();
    final unstaged = data.working.where((f) => f.isUnstaged).toList();
    final clean = data.working.isEmpty;

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: 'CHANGES'),
          Expanded(
            child: clean
                ? _CleanState()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      _FileSection(
                        label: 'STAGED',
                        files: staged,
                        staged: true,
                        onBulk: actions.unstageAll,
                        bulkLabel: 'Unstage all',
                        onToggle: (f) => actions.unstageFile(f.path),
                        onOpen: (f) => _open(ref, f.path),
                      ),
                      _FileSection(
                        label: 'UNSTAGED',
                        files: unstaged,
                        staged: false,
                        onBulk: actions.stageAll,
                        bulkLabel: 'Stage all',
                        onToggle: (f) => actions.stageFile(f.path),
                        onOpen: (f) => _open(ref, f.path),
                      ),
                    ],
                  ),
          ),
          if (!clean) _Composer(repoPath: repoPath, stagedCount: staged.length),
        ],
      ),
    );
  }

  void _open(WidgetRef ref, String path) =>
      ref.read(diffTargetProvider.notifier).state = DiffTarget(
        repoPath: repoPath,
        path: path,
      );
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: t.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CleanState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: t.success, size: 26),
          const SizedBox(height: 10),
          Text(
            'Working tree clean',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            'Nothing to commit',
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FileSection extends StatelessWidget {
  final String label;
  final List<WorkingFile> files;
  final bool staged;
  final VoidCallback onBulk;
  final String bulkLabel;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;

  const _FileSection({
    required this.label,
    required this.files,
    required this.staged,
    required this.onBulk,
    required this.bulkLabel,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(
            children: [
              Text(
                '$label (${files.length})',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (files.isNotEmpty)
                TextButton(
                  onPressed: onBulk,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(bulkLabel, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        for (final f in files)
          _FileRow(file: f, staged: staged, onToggle: onToggle, onOpen: onOpen),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final WorkingFile file;
  final bool staged;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;

  const _FileRow({
    required this.file,
    required this.staged,
    required this.onToggle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final change = staged ? file.index : file.worktree;
    final (color, letter) = switch (change) {
      GitChange.added => (t.success, 'A'),
      GitChange.deleted => (t.danger, 'D'),
      GitChange.renamed => (t.accent, 'R'),
      GitChange.untracked => (t.success, 'U'),
      GitChange.conflicted => (t.danger, '!'),
      _ => (t.warning, 'M'),
    };
    // Tri-state: staged section shows filled unless partial; unstaged empty
    // unless partial.
    final bool? value = file.isPartial ? null : (staged ? true : false);

    return InkWell(
      onTap: () => onOpen(file),
      hoverColor: t.hover,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                tristate: true,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => onToggle(file),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                file.path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textMuted, fontSize: 12.5),
              ),
            ),
            if (file.isPartial)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: t.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'partial',
                  style: TextStyle(
                    color: t.warning,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              letter,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  final String repoPath;
  final int stagedCount;
  const _Composer({required this.repoPath, required this.stagedCount});

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _summary = TextEditingController();
  final _description = TextEditingController();
  var _amend = false;
  var _sign = false;

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final toasts = ref.read(toastProvider.notifier);
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      toasts.show('Commit message is empty', kind: ToastKind.warning);
      return;
    }
    if (!_amend && widget.stagedCount == 0) {
      toasts.show('Nothing staged to commit', kind: ToastKind.warning);
      return;
    }
    try {
      await ref
          .read(repoActionsProvider(widget.repoPath))
          .commit(
            summary,
            description: _description.text,
            amend: _amend,
            sign: _sign,
          );
      _summary.clear();
      _description.clear();
      setState(() => _amend = false);
      toasts.show('Committed', kind: ToastKind.success);
    } on Object catch (e) {
      toasts.show('Commit failed', description: '$e', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(top: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _summary,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
            decoration: _dec(t, 'Summary'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            style: TextStyle(color: t.textMuted, fontSize: 12.5),
            maxLines: 3,
            minLines: 2,
            decoration: _dec(t, 'Description'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Toggle(
                label: 'Amend',
                value: _amend,
                onChanged: (v) => setState(() => _amend = v),
              ),
              const SizedBox(width: 12),
              _Toggle(
                label: 'Sign',
                value: _sign,
                onChanged: (v) => setState(() => _sign = v),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _commit,
                child: Text(_amend ? 'Amend' : 'Commit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(AppTokens t, String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: t.textFaint, fontSize: 12.5),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    filled: true,
    fillColor: t.bgApp,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: t.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: t.border),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: value ? t.accent : t.textFaint,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: t.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
