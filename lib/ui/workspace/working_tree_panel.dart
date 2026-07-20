import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_reader.dart';
import '../../domain/git/models.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/profiles.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../common/file_tree_view.dart';
import '../insight/file_insight_dialog.dart';

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
    final tree = ref.watch(settingsProvider.select((s) => s.filesAsTree));

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: 'CHANGES',
            trailing: clean ? null : const FileViewToggle(),
          ),
          Expanded(
            child: clean
                ? _CleanState()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      _FileSection(
                        label: 'STAGED',
                        repoPath: repoPath,
                        files: staged,
                        staged: true,
                        tree: tree,
                        onBulk: actions.unstageAll,
                        bulkLabel: 'Unstage all',
                        onToggle: (f) => actions.unstageFile(f.path),
                        onOpen: (f) => _open(ref, f.path),
                      ),
                      _FileSection(
                        label: 'UNSTAGED',
                        repoPath: repoPath,
                        files: unstaged,
                        staged: false,
                        tree: tree,
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
  final Widget? trailing;
  const _Header({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
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
  final String repoPath;
  final List<WorkingFile> files;
  final bool staged;
  final bool tree;
  final VoidCallback onBulk;
  final String bulkLabel;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;

  const _FileSection({
    required this.label,
    required this.repoPath,
    required this.files,
    required this.staged,
    required this.tree,
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
        FileTreeView(
          paths: [for (final f in files) f.path],
          tree: tree,
          fileRow: (path, depth) => _FileRow(
            file: byPath[path]!,
            repoPath: repoPath,
            staged: staged,
            indent: FileTreeView.indent(depth),
            inTree: tree,
            onToggle: onToggle,
            onOpen: onOpen,
          ),
        ),
      ],
    );
  }

  Map<String, WorkingFile> get byPath => {for (final f in files) f.path: f};
}

class _FileRow extends StatelessWidget {
  final WorkingFile file;
  final String repoPath;
  final bool staged;
  final double indent;
  final bool inTree;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;

  const _FileRow({
    required this.file,
    required this.repoPath,
    required this.staged,
    required this.onToggle,
    required this.onOpen,
    this.indent = 0,
    this.inTree = false,
  });

  String get _label {
    if (!inTree) return file.path;
    final i = file.path.lastIndexOf('/');
    return i < 0 ? file.path : file.path.substring(i + 1);
  }

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

    return GestureDetector(
      onSecondaryTapUp: (d) => showContextMenu<void>(
        context: context,
        position: d.globalPosition,
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
      ),
      child: InkWell(
        onTap: () => onOpen(file),
        hoverColor: t.hover,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10 + indent, 4, 10, 4),
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
                  _label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textMuted, fontSize: 12.5),
                ),
              ),
              if (file.isPartial)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
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
  final _coauthors = TextEditingController();
  var _amend = false;
  var _sign = false;
  var _showCoauthors = false;
  // Text the amend toggle itself prefilled (summary + description), so turning
  // it off can clear each field only if the user hasn't since edited it.
  String? _amendPrefillSummary;
  String? _amendPrefillDescription;

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    _coauthors.dispose();
    super.dispose();
  }

  /// Comma-separated `Name <email>` entries → trimmed list.
  List<String> get _coauthorList => [
    for (final c in _coauthors.text.split(','))
      if (c.trim().isNotEmpty) c.trim(),
  ];

  /// Turning Amend on pre-fills the composer with HEAD's message so the user
  /// edits the real text instead of retyping it. Turning it off clears the
  /// prefill again — but only if the user has not since edited it.
  Future<void> _setAmend(bool v) async {
    setState(() => _amend = v);
    if (!v) {
      // Clear each field on toggle-off only if it still holds exactly what the
      // toggle prefilled — an edited field is the user's, and is left alone.
      setState(() {
        if (_amendPrefillSummary != null &&
            _summary.text == _amendPrefillSummary) {
          _summary.clear();
        }
        if (_amendPrefillDescription != null &&
            _description.text == _amendPrefillDescription) {
          _description.clear();
        }
      });
      _amendPrefillSummary = null;
      _amendPrefillDescription = null;
      return;
    }
    if (_summary.text.trim().isNotEmpty) return; // don't clobber typed text
    final msg = await GitReader(
      ref.read(gitServiceProvider),
      widget.repoPath,
    ).lastCommitMessage();
    // Re-check after the await: the user may have toggled amend back off or
    // started typing while `git log` ran — never overwrite that.
    if (!mounted || !_amend || msg.isEmpty || _summary.text.isNotEmpty) return;
    final nl = msg.indexOf('\n');
    final summary = nl == -1 ? msg : msg.substring(0, nl);
    final description = nl == -1 ? '' : msg.substring(nl + 1).trim();
    setState(() {
      _summary.text = summary;
      _description.text = description;
    });
    _amendPrefillSummary = summary;
    _amendPrefillDescription = description;
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
            coauthors: _coauthorList,
          );
      _summary.clear();
      _description.clear();
      _coauthors.clear();
      setState(() {
        _amend = false;
        _showCoauthors = false;
      });
      toasts.show('Committed', kind: ToastKind.success);
    } on Object catch (e) {
      toasts.show('Commit failed', description: '$e', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final profile = ref.watch(profilesProvider).active;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _commit,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _commit,
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.bgPanel,
          border: Border(top: BorderSide(color: t.border)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile != null) ...[
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(profile.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${profile.name} <${profile.email}>',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textFaint, fontSize: 11),
                    ),
                  ),
                  if (_sign) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.verified_user_outlined,
                      size: 11,
                      color: t.success,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
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
            if (_showCoauthors) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _coauthors,
                style: TextStyle(color: t.textMuted, fontSize: 12),
                decoration: _dec(t, 'Co-authors: Name <email>, Name2 <email2>'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                // Toggles wrap to a second line when the panel is narrow so the
                // Commit button stays pinned right and never clips off-panel.
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Toggle(
                        label: 'Amend',
                        value: _amend,
                        onChanged: _setAmend,
                      ),
                      _Toggle(
                        label: 'Sign',
                        value: _sign,
                        onChanged: (v) => setState(() => _sign = v),
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _showCoauthors = !_showCoauthors),
                        child: Text(
                          '+ Co-author',
                          style: TextStyle(
                            color: _showCoauthors ? t.accent : t.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: '⌘⏎',
                  child: FilledButton(
                    onPressed: _commit,
                    child: Text(_amend ? 'Amend' : 'Commit'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
