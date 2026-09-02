import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/commit_message.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_reader.dart';
import '../../domain/git/models.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/merge_session.dart';
import '../../state/profiles.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../common/file_tree_view.dart';
import '../insight/file_insight_dialog.dart';
import '../../l10n/gen/app_localizations.dart';

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
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final actions = ref.read(repoActionsProvider(repoPath));
    final staged = data.working.where((f) => f.isStaged).toList();
    final unstaged = data.working.where((f) => f.isUnstaged).toList();
    final clean = data.working.isEmpty;
    final tree = ref.watch(settingsProvider.select((s) => s.filesAsTree));
    final hasConflicts = data.working.any((f) => f.isConflicted);
    final resolving = ref.watch(mergeSessionProvider(repoPath)) != null;
    final pending = ref.watch(pendingOpProvider(repoPath)).valueOrNull;

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: l.wtpChanges,
            trailing: clean
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 15,
                        visualDensity: VisualDensity.compact,
                        tooltip: l.wtpDiscardAll,
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: () => _confirmDiscardAll(
                          ref,
                          context,
                          repoPath,
                          untracked: data.working
                              .where((f) => f.isUntracked)
                              .length,
                        ),
                      ),
                      const FileViewToggle(),
                    ],
                  ),
          ),
          if (hasConflicts && !resolving)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: actions.openConflictResolution,
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: Text(l.mergeResolveConflicts),
                ),
              ),
            )
          else if (!resolving && pending != null)
            _PendingOpBar(repoPath: repoPath, pending: pending),
          Expanded(
            child: clean
                ? _CleanState()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      _FileSection(
                        label: l.wtpUnstaged,
                        repoPath: repoPath,
                        files: unstaged,
                        staged: false,
                        tree: tree,
                        onBulk: actions.stageAll,
                        bulkLabel: l.wtpStageAll,
                        onToggle: (f) => actions.stageFile(f.path),
                        onOpen: (f) => _open(ref, f.path, staged: false),
                        onDiscard: (f) =>
                            _confirmDiscardFile(ref, context, repoPath, f),
                      ),
                      _FileSection(
                        label: l.wtpStaged,
                        repoPath: repoPath,
                        files: staged,
                        staged: true,
                        tree: tree,
                        onBulk: actions.unstageAll,
                        bulkLabel: l.wtpUnstageAll,
                        onToggle: (f) => actions.unstageFile(f.path),
                        onOpen: (f) => _open(ref, f.path, staged: true),
                        onDiscard: (f) =>
                            _confirmDiscardFile(ref, context, repoPath, f),
                      ),
                    ],
                  ),
          ),
          // A merge whose resolution matched HEAD leaves a clean tree, and the
          // merge commit is still owed — the composer has to stay reachable.
          if (!clean || pending?.kind == MergeKind.merge)
            _Composer(
              repoPath: repoPath,
              stagedCount: staged.length,
              // A paused sequence commits through its own --continue; a stray
              // commit here would strand the rest of the sequence.
              sequencePaused: pending?.continues ?? false,
              merging: pending?.kind == MergeKind.merge,
            ),
        ],
      ),
    );
  }

  void _open(WidgetRef ref, String path, {required bool staged}) =>
      ref.read(diffTargetProvider.notifier).state = DiffTarget(
        repoPath: repoPath,
        path: path,
        staged: staged,
      );
}

/// Sits above the file lists while git is still in the middle of an operation
/// whose conflicts are already resolved and staged. It names what is waiting
/// and offers the one action that closes it — except for a merge, which closes
/// through an ordinary commit, so that one only explains itself.
class _PendingOpBar extends ConsumerWidget {
  final String repoPath;
  final PendingOp pending;
  const _PendingOpBar({required this.repoPath, required this.pending});

  static String _name(MergeKind kind) => switch (kind) {
    MergeKind.rebase => 'rebase',
    MergeKind.cherryPick => 'cherry-pick',
    MergeKind.revert => 'revert',
    _ => 'merge',
  };

  Future<void> _abort(WidgetRef ref, BuildContext context) async {
    final l = AppLocalizations.of(context);
    final name = _name(pending.kind);
    final ok = await confirmDestructive(
      ref,
      context,
      title: l.wtpAbortTitle(name),
      body: l.wtpAbortBody(name),
      confirmLabel: l.wtpAbort,
    );
    if (ok) await ref.read(repoActionsProvider(repoPath)).abortMerge();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final name = _name(pending.kind);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.pending_outlined, size: 14, color: t.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // Not always a resolution the app just staged: a merge or
                  // rebase started in a terminal lands here the same way.
                  pending.continues
                      ? l.wtpOpPausedBody(name)
                      : l.wtpMergeOpenBody,
                  style: TextStyle(color: t.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (pending.continues) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: ref
                        .read(repoActionsProvider(repoPath))
                        .continueOp,
                    child: Text(l.wtpContinueOp(name)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _abort(ref, context),
                  child: Text(l.wtpAbort),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: t.success, size: 26),
          const SizedBox(height: 10),
          Text(
            l.wtpTreeClean,
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            l.wtpNothingToCommit,
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
  final void Function(WorkingFile) onDiscard;

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
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(
            children: [
              Text(
                l.wtpSectionCount(label, files.length),
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
            onDiscard: onDiscard,
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
  final void Function(WorkingFile) onDiscard;

  const _FileRow({
    required this.file,
    required this.repoPath,
    required this.staged,
    required this.onToggle,
    required this.onOpen,
    required this.onDiscard,
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
    final l = AppLocalizations.of(context);
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
          PopupMenuItem(
            height: 34,
            onTap: () => onDiscard(file),
            child: Text(l.wtpDiscardChanges, style: TextStyle(fontSize: 13)),
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

  /// A rebase/cherry-pick/revert is paused: committing is not the way to
  /// finish it, so the composer is held shut until it is continued or aborted.
  final bool sequencePaused;

  /// A merge is open, so this commit closes it — and git has a message ready.
  final bool merging;
  const _Composer({
    required this.repoPath,
    required this.stagedCount,
    required this.sequencePaused,
    required this.merging,
  });

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
  void didUpdateWidget(_Composer old) {
    super.didUpdateWidget(old);
    if (widget.merging && !old.merging) _prefillMergeMessage();
  }

  @override
  void initState() {
    super.initState();
    if (widget.merging) _prefillMergeMessage();
  }

  /// Offers git's prepared merge message ("Merge branch 'x'") once a merge is
  /// waiting to be committed, so the user edits real text instead of retyping
  /// it. Never overwrites anything already in the field.
  Future<void> _prefillMergeMessage() async {
    if (_summary.text.trim().isNotEmpty) return;
    final msg = await ref
        .read(repoActionsProvider(widget.repoPath))
        .pendingMergeMessage();
    // Re-check after the await: the user may have started typing meanwhile.
    if (!mounted || msg.isEmpty || _summary.text.isNotEmpty) return;
    final (:summary, :description) = splitCommitMessage(msg);
    setState(() {
      _summary.text = summary;
      _description.text = description;
    });
  }

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
    final (:summary, :description) = splitCommitMessage(msg);
    setState(() {
      _summary.text = summary;
      _description.text = description;
    });
    _amendPrefillSummary = summary;
    _amendPrefillDescription = description;
  }

  Future<void> _commit() async {
    final l = AppLocalizations.of(context);
    final toasts = ref.read(toastProvider.notifier);
    if (widget.sequencePaused) {
      toasts.show(
        l.wtpFinishOpFirst,
        description: l.wtpFinishOpBody,
        kind: ToastKind.warning,
      );
      return;
    }
    final summary = _summary.text.trim();
    if (summary.isEmpty) {
      toasts.show(l.wtpMessageEmpty, kind: ToastKind.warning);
      return;
    }
    // A merge commit is worth making even with nothing staged: it records the
    // merge itself, which is not otherwise in the history.
    if (!_amend && !widget.merging && widget.stagedCount == 0) {
      toasts.show(l.wtpNothingStaged, kind: ToastKind.warning);
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
      toasts.show(l.wtpCommitted, kind: ToastKind.success);
    } on Object catch (e) {
      toasts.show(l.wtpCommitFailed, description: '$e', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              decoration: _dec(t, l.wtpSummary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              style: TextStyle(color: t.textMuted, fontSize: 12.5),
              maxLines: 3,
              minLines: 2,
              decoration: _dec(t, l.wtpDescription),
            ),
            if (_showCoauthors) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _coauthors,
                style: TextStyle(color: t.textMuted, fontSize: 12),
                decoration: _dec(t, l.wtpCoauthorsHint),
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
                        label: l.wtpAmend,
                        value: _amend,
                        onChanged: _setAmend,
                      ),
                      _Toggle(
                        label: l.wtpSign,
                        value: _sign,
                        onChanged: (v) => setState(() => _sign = v),
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _showCoauthors = !_showCoauthors),
                        child: Text(
                          l.wtpAddCoauthor,
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
                    onPressed: widget.sequencePaused ? null : _commit,
                    child: Text(_amend ? l.wtpAmend : l.wtpCommit),
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

/// Confirms discarding the whole working tree, then performs it. [untracked]
/// is how many untracked files are present; when there are any, the prompt
/// carries an opt-in to delete them as well, off by default — reverting a
/// tracked file has a committed state to come back to, while deleting a new
/// file does not, so the two are not offered as one blanket action.
///
/// Unlike [_confirmDiscardFile] this prompt is shown even when "confirm
/// destructive actions" is off: it collects a choice, not just an acknowledgement.
Future<void> _confirmDiscardAll(
  WidgetRef ref,
  BuildContext context,
  String repoPath, {
  required int untracked,
}) async {
  var deleteUntracked = false;
  final l = AppLocalizations.of(context);
  final t = context.tokens;
  final ok = await showAppModal<bool>(
    context: context,
    title: l.wtpDiscardAllTitle,
    icon: Icons.warning_amber_rounded,
    width: 460,
    body: StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.wtpDiscardAllBody,
            style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
          ),
          if (untracked > 0) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => deleteUntracked = !deleteUntracked),
              child: Row(
                children: [
                  Checkbox(
                    value: deleteUntracked,
                    onChanged: (v) =>
                        setState(() => deleteUntracked = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      l.wtpAlsoDeleteUntracked(untracked),
                      style: TextStyle(color: t.textMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.tokens.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.discard),
        ),
      ),
    ],
  );
  if (ok != true) return;
  await ref
      .read(repoActionsProvider(repoPath))
      .discardAll(includeUntracked: deleteUntracked);
}

/// Confirms discarding [f], then performs it. A tracked file is fully
/// reverted to its committed state; an untracked file is deleted. Either way
/// the action is undoable, so the confirm copy says so.
Future<void> _confirmDiscardFile(
  WidgetRef ref,
  BuildContext context,
  String repoPath,
  WorkingFile f,
) async {
  final l = AppLocalizations.of(context);
  final ok = await confirmDestructive(
    ref,
    context,
    title: l.wtpDiscardFileTitle(f.path),
    body: f.isUntracked ? l.diffDiscardFileBody : l.wtpDiscardFileBody,
    confirmLabel: l.discard,
  );
  if (!ok) return;
  await ref.read(repoActionsProvider(repoPath)).discardFile(f);
}
