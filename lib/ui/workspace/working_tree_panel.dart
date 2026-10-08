import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/forge/models.dart';
import '../../domain/git/commit_message.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_reader.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../domain/git/rebase_plan.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/commit_composer.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/hooks.dart';
import '../../state/lfs.dart';
import '../../state/merge_session.dart';
import '../../state/profiles.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../common/file_tree_view.dart';
import '../common/lfs_chip.dart';
import '../common/lfs_lock_chip.dart';
import '../insight/file_insight_dialog.dart';
import 'hooks_panel.dart';
import 'lfs_banner.dart';
import 'lfs_lock_menu.dart';
import 'lfs_locks_section.dart';
import 'lfs_track_menu.dart';
import 'lfs_pointer_strip.dart';

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
    // One lookup for every changed path; the sections pick from it.
    final lfs =
        ref
            .watch(
              lfsPathsProvider(workingTreeLfsQuery(repoPath, data.working)),
            )
            .valueOrNull ??
        const <String>{};
    // Read once for every row; each row picks its own path from it.
    final locks =
        ref.watch(lfsLocksProvider(repoPath)).valueOrNull ?? LfsLockState.none;
    // Watched so the menu gains or loses its LFS entries once git-lfs is known.
    ref.watch(lfsToolProvider);
    List<PopupMenuEntry<void>> trackItems(WorkingFile f, bool isLfs) => [
      ...lfsTrackMenuItems(
        context: context,
        ref: ref,
        repoPath: repoPath,
        file: f,
        isLfs: isLfs,
      ),
      ...lfsLockMenuItems(
        context: context,
        ref: ref,
        repoPath: repoPath,
        path: f.path,
        isLfs: isLfs,
        submodule: f.submodule,
      ),
    ];

    return Semantics(
      container: true,
      label: l.a11yWorkingChanges,
      child: Container(
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
            LfsBanner(repoPath: repoPath, working: data.working),
            LfsPointerStrip(repoPath: repoPath, working: data.working),
            LfsLocksSection(repoPath: repoPath, working: data.working),
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
                          lfs: lfs,
                          locks: locks,
                          onBulk: actions.stageAll,
                          bulkLabel: l.wtpStageAll,
                          onToggle: (f) => actions.stageFile(f.path),
                          onOpen: (f) => _open(ref, f.path, staged: false),
                          onDiscard: (f) =>
                              _confirmDiscardFile(ref, context, repoPath, f),
                          trackItems: trackItems,
                        ),
                        _FileSection(
                          label: l.wtpStaged,
                          repoPath: repoPath,
                          files: staged,
                          staged: true,
                          tree: tree,
                          lfs: lfs,
                          locks: locks,
                          onBulk: actions.unstageAll,
                          bulkLabel: l.wtpUnstageAll,
                          onToggle: (f) => actions.unstageFile(f.path),
                          onOpen: (f) => _open(
                            ref,
                            f.path,
                            staged: true,
                            origPath: f.origPath,
                          ),
                          onDiscard: (f) =>
                              _confirmDiscardFile(ref, context, repoPath, f),
                          trackItems: trackItems,
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
                branch:
                    data.branches.where((b) => b.current).firstOrNull?.name ??
                    'HEAD',
                // A paused sequence commits through its own --continue; a stray
                // commit here would strand the rest of the sequence. A rebase
                // stopped on a break or a failed exec is the exception: making
                // or amending a commit there is what the stop is for.
                sequencePaused:
                    (pending?.continues ?? false) && pending?.stop == null,
                merging: pending?.kind == MergeKind.merge,
              ),
          ],
        ),
      ),
    );
  }

  /// [origPath] names where a staged rename came from; without it git sees
  /// only the new name and reports the file as added.
  void _open(
    WidgetRef ref,
    String path, {
    required bool staged,
    String? origPath,
  }) => ref.read(diffTargetProvider.notifier).state = DiffTarget(
    repoPath: repoPath,
    path: path,
    staged: staged,
    origPath: origPath,
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
                  switch (pending.stop) {
                    RebaseStop(:final command?) => l.wtpExecFailedBody(command),
                    RebaseStop(kind: RebaseStopKind.reword) =>
                      l.wtpRewordRejectedBody,
                    RebaseStop() => l.wtpBreakPausedBody,
                    null when pending.continues => l.wtpOpPausedBody(name),
                    null => l.wtpMergeOpenBody,
                  },
                  style: TextStyle(color: t.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          if (pending.stop?.failed ?? false) _ExecOutput(repoPath: repoPath),
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
  final Set<String> lfs;
  final LfsLockState locks;
  final VoidCallback onBulk;
  final String bulkLabel;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;
  final void Function(WorkingFile) onDiscard;
  final List<PopupMenuEntry<void>> Function(WorkingFile, bool) trackItems;

  const _FileSection({
    required this.label,
    required this.repoPath,
    required this.files,
    required this.staged,
    required this.tree,
    required this.lfs,
    required this.locks,
    required this.onBulk,
    required this.bulkLabel,
    required this.onToggle,
    required this.onOpen,
    required this.onDiscard,
    required this.trackItems,
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
            lfs: lfs.contains(path),
            lock: locks.lockFor(path),
            lockIsOurs: locks.isOurs(path),
            onToggle: onToggle,
            onOpen: onOpen,
            onDiscard: onDiscard,
            trackItems: trackItems,
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
  final bool lfs;
  final LfsLock? lock;
  final bool lockIsOurs;
  final void Function(WorkingFile) onToggle;
  final void Function(WorkingFile) onOpen;
  final void Function(WorkingFile) onDiscard;
  final List<PopupMenuEntry<void>> Function(WorkingFile, bool) trackItems;

  const _FileRow({
    required this.file,
    required this.repoPath,
    required this.staged,
    required this.onToggle,
    required this.onOpen,
    required this.onDiscard,
    required this.trackItems,
    this.indent = 0,
    this.inTree = false,
    this.lfs = false,
    this.lock,
    this.lockIsOurs = false,
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
          ...trackItems(file, lfs),
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
              if (lfs) const LfsChip(),
              if (lfs && lock != null)
                LfsLockChip(lock: lock!, ours: lockIsOurs),
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

/// What the failed step printed, folded away until asked for: it can be
/// a whole test run, and the bar above the file lists is no place to dump it.
class _ExecOutput extends ConsumerStatefulWidget {
  final String repoPath;
  const _ExecOutput({required this.repoPath});

  @override
  ConsumerState<_ExecOutput> createState() => _ExecOutputState();
}

class _ExecOutputState extends ConsumerState<_ExecOutput> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final out = ref.watch(rebaseExecOutputProvider(widget.repoPath));
    if (out == null || out.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? l.wtpHideOutput : l.wtpShowOutput),
          ),
        ),
        if (_open)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.bgElevated,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                out,
                style: AppFonts.mns(size: 11, color: t.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  final String repoPath;
  final int stagedCount;

  /// The checked-out branch (`HEAD` when detached): drafts are kept per
  /// branch, so switching away and back finds the message where it was left.
  final String branch;

  /// A rebase/cherry-pick/revert is paused: committing is not the way to
  /// finish it, so the composer is held shut until it is continued or aborted.
  final bool sequencePaused;

  /// A merge is open, so this commit closes it — and git has a message ready.
  final bool merging;
  const _Composer({
    required this.repoPath,
    required this.stagedCount,
    required this.branch,
    required this.sequencePaused,
    required this.merging,
  });

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

/// Width the description is wrapped to: what `git log` readers expect.
const _wrapWidth = 72;

/// The subject lengths the composer menu offers to measure against.
const _subjectLimits = [50, 72, 100];

class _ComposerState extends ConsumerState<_Composer> {
  final _summary = TextEditingController();
  final _description = TextEditingController();
  final _coauthors = TextEditingController();
  final _refs = TextEditingController();
  final _fixes = TextEditingController();
  final _scope = TextEditingController();
  // Owned here rather than by the dialog: the dialog's closing animation
  // still draws the field after its future has completed.
  final _templateEditor = TextEditingController();
  var _type = '';
  var _breaking = false;
  var _amend = false;
  var _sign = false;
  var _signoff = false;
  var _showTrailers = false;
  // Text the amend toggle itself prefilled (summary + description), so turning
  // it off can clear each field only if the user hasn't since edited it.
  String? _amendPrefillSummary;
  String? _amendPrefillDescription;

  late final ComposerStore _store;
  ({String text, String commentChar})? _template;
  // The message as the template left it; while the composer still holds
  // exactly this it counts as empty — anything else may replace it.
  String? _appliedTemplate;
  // The branch's draft has been looked up. Until then nothing is saved, so a
  // switch cannot overwrite the draft it is about to restore.
  var _draftReady = false;
  Timer? _draftTimer;
  var _recent = const <String>[];
  // Mirrors the repository's prefs, kept in a field so the message can still
  // be composed in dispose, where ref is no longer usable.
  var _conventional = false;

  @override
  void didUpdateWidget(_Composer old) {
    super.didUpdateWidget(old);
    if (widget.branch != old.branch) _switchBranch(old.branch);
    if (widget.merging && !old.merging) _prefillMergeMessage();
  }

  @override
  void initState() {
    super.initState();
    _store = ref.read(composerStoreProvider(widget.repoPath));
    ref.listenManual(
      composerPrefsProvider(widget.repoPath),
      (_, p) => _conventional = p.conventional,
      fireImmediately: true,
    );
    for (final c in _controllers) {
      c.addListener(_edited);
    }
    if (widget.merging) _prefillMergeMessage();
    // A message another part of the app prepared (a fixup, say) — whether it
    // was set before this composer existed or while it is on screen.
    ref.listenManual(
      composerPrefillProvider(widget.repoPath),
      (_, next) => _takePrefill(next),
      fireImmediately: true,
    );
    ref.listenManual(commitTemplateProvider(widget.repoPath), (_, next) {
      final t = next.valueOrNull;
      if (t == null) return;
      _template = t;
      _applyTemplateIfPristine();
    }, fireImmediately: true);
    _restoreDraft();
    _loadRecent();
  }

  List<TextEditingController> get _controllers => [
    _summary,
    _description,
    _coauthors,
    _refs,
    _fixes,
    _scope,
  ];

  /// The subject as it will be committed: the summary, behind its
  /// Conventional Commits prefix when that mode is on.
  String get _subject => _conventional
      ? formatConventionalSubject((
          type: _type,
          scope: _scope.text,
          breaking: _breaking,
          description: _summary.text,
        ))
      : _summary.text.trim();

  String get _message => joinCommitMessage(_subject, _description.text);

  bool get _trailersEmpty =>
      [_coauthors, _refs, _fixes].every((c) => c.text.trim().isEmpty);

  /// Nothing of the user's in the composer: empty, or exactly the template.
  bool get _pristine =>
      _trailersEmpty &&
      (_message.isEmpty ||
          (_appliedTemplate != null && _message == _appliedTemplate));

  void _edited() {
    if (!mounted) return;
    setState(() {});
    if (!_draftReady) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  ComposerDraft get _draft => _pristine
      ? const ComposerDraft()
      : ComposerDraft(
          summary: _summary.text,
          description: _description.text,
          coauthors: _coauthors.text,
          refs: _refs.text,
          fixes: _fixes.text,
          type: _type,
          scope: _scope.text,
          breaking: _breaking,
        );

  /// Keeps what is typed for the current branch. An amend's text is HEAD's
  /// message, not something the user started, so it is not kept.
  void _saveDraft([String? branch]) {
    _draftTimer?.cancel();
    if (!_draftReady || _amend) return;
    _store.saveDraft(branch ?? widget.branch, _draft);
  }

  Future<void> _restoreDraft() async {
    final branch = widget.branch;
    final draft = await _store.draft(branch);
    if (!mounted || branch != widget.branch) return;
    _draftReady = true;
    if (draft != null && _pristine) {
      setState(() {
        _summary.text = draft.summary;
        _description.text = draft.description;
        _coauthors.text = draft.coauthors;
        _refs.text = draft.refs;
        _fixes.text = draft.fixes;
        _scope.text = draft.scope;
        _type = draft.type;
        _breaking = draft.breaking;
        _showTrailers = !_trailersEmpty;
        _appliedTemplate = null;
      });
    } else {
      _applyTemplateIfPristine();
    }
  }

  /// Leaving [from]: its message is kept for it, and the composer starts over
  /// with whatever the new branch left behind.
  void _switchBranch(String from) {
    _saveDraft(from);
    _draftReady = false;
    for (final c in _controllers) {
      c.clear();
    }
    _type = '';
    _breaking = false;
    _amend = false;
    _amendPrefillSummary = null;
    _amendPrefillDescription = null;
    _appliedTemplate = null;
    _showTrailers = false;
    _restoreDraft();
  }

  Future<void> _loadRecent() async {
    final recent = await _store.recent();
    if (mounted) setState(() => _recent = recent);
  }

  void _applyTemplateIfPristine() {
    final t = _template;
    if (!_draftReady || t == null || !_pristine) return;
    if (t.text.isEmpty && _appliedTemplate == null) return;
    _putMessage(t.text);
    _appliedTemplate = t.text.isEmpty ? null : _message;
  }

  /// Fills the message fields with [message]. In Conventional Commits mode a
  /// conventional subject is taken apart into the type row; any other subject
  /// is kept whole, with no type, so nothing is prefixed onto it.
  void _putMessage(String message) {
    final (:summary, :description) = splitCommitMessage(message);
    setState(() {
      final parsed = _conventional ? parseConventionalSubject(summary) : null;
      _type = parsed?.type ?? '';
      _scope.text = parsed?.scope ?? '';
      _breaking = parsed?.breaking ?? false;
      _summary.text = parsed?.description ?? summary;
      _description.text = description;
      _appliedTemplate = null;
    });
  }

  /// Puts [message] in the summary field and clears the request, so a rebuild
  /// does not apply it twice. Asked for explicitly, so it replaces what is
  /// typed rather than waiting for an empty field.
  void _takePrefill(String? message) {
    if (message == null) return;
    _putMessage(message);
    // Not inside the notification itself: a provider cannot be written while
    // it is still telling its listeners about the last write.
    Future.microtask(() {
      if (!mounted) return;
      final prefill = ref.read(
        composerPrefillProvider(widget.repoPath).notifier,
      );
      if (prefill.state == message) prefill.state = null;
    });
  }

  /// Offers git's prepared merge message ("Merge branch 'x'") once a merge is
  /// waiting to be committed, so the user edits real text instead of retyping
  /// it. Never overwrites anything the user typed.
  Future<void> _prefillMergeMessage() async {
    if (!_pristine) return;
    final msg = await ref
        .read(repoActionsProvider(widget.repoPath))
        .pendingMergeMessage();
    // Re-check after the await: the user may have started typing meanwhile.
    if (!mounted || msg.isEmpty || !_pristine) return;
    _putMessage(msg);
  }

  @override
  void dispose() {
    _saveDraft();
    for (final c in _controllers) {
      c.dispose();
    }
    _templateEditor.dispose();
    super.dispose();
  }

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
      _applyTemplateIfPristine();
      return;
    }
    if (!_pristine) return; // don't clobber typed text
    final msg = await GitReader(
      ref.read(gitServiceProvider),
      widget.repoPath,
    ).lastCommitMessage();
    // Re-check after the await: the user may have toggled amend back off or
    // started typing while `git log` ran — never overwrite that.
    if (!mounted || !_amend || msg.isEmpty || !_pristine) return;
    _putMessage(msg);
    _amendPrefillSummary = _summary.text;
    _amendPrefillDescription = _description.text;
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
    final subject = _subject;
    if (_summary.text.trim().isEmpty) {
      toasts.show(l.wtpMessageEmpty, kind: ToastKind.warning);
      return;
    }
    // git refuses a message left exactly as its template offered it; so does
    // the composer, rather than commit the template's placeholder text.
    final template = _template;
    if (template != null &&
        isUntouchedTemplate(
          _message,
          template.text,
          commentChar: template.commentChar,
        )) {
      toasts.show(
        l.wtpTemplateUntouched,
        description: l.wtpTemplateUntouchedBody,
        kind: ToastKind.warning,
      );
      return;
    }
    // A merge commit is worth making even with nothing staged: it records the
    // merge itself, which is not otherwise in the history.
    if (!_amend && !widget.merging && widget.stagedCount == 0) {
      toasts.show(l.wtpNothingStaged, kind: ToastKind.warning);
      return;
    }
    final skipHooks = skipHooksOnceProvider(widget.repoPath);
    final branch = widget.branch;
    final message = _message;
    try {
      final outcome = await ref
          .read(repoActionsProvider(widget.repoPath))
          .commit(
            subject,
            description: _description.text,
            amend: _amend,
            sign: _sign,
            noVerify: ref.read(skipHooks),
            signoff: _signoff,
            coauthors: splitList(_coauthors.text),
            trailers: buildTrailers(
              refs: splitList(_refs.text),
              fixes: splitList(_fixes.text),
            ),
          );
      // Anything short of a commit keeps the message: the failure has been
      // reported already, and retyping it is the last thing the user needs.
      if (!outcome.committed) {
        final rejection = outcome.rejection;
        if (rejection != null && mounted) {
          final armSkip = ref.read(skipHooks.notifier);
          await showHookRejectedDialog(
            context,
            repoPath: widget.repoPath,
            rejection: rejection,
            skipLabel: l.hkSkipNext,
            onSkip: () async => armSkip.state = true,
          );
        }
        return;
      }
      ref.read(skipHooks.notifier).state = false;
      _draftTimer?.cancel();
      await _store.saveDraft(branch, const ComposerDraft());
      await _store.remember(message);
      if (!mounted) return;
      for (final c in _controllers) {
        c.clear();
      }
      setState(() {
        _amend = false;
        _type = '';
        _breaking = false;
        _showTrailers = false;
        _appliedTemplate = null;
      });
      _applyTemplateIfPristine();
      _loadRecent();
      toasts.show(l.wtpCommitted, kind: ToastKind.success);
    } on Object catch (e) {
      toasts.show(l.wtpCommitFailed, description: '$e', kind: ToastKind.error);
    }
  }

  Future<void> _setConventional(bool on) async {
    final subject = _subject;
    await ref
        .read(composerPrefsProvider(widget.repoPath).notifier)
        .update((p) => p.copyWith(conventional: on));
    if (!mounted) return;
    final applied = _appliedTemplate;
    // Re-read the subject under the new mode: typed `fix(x): y` splits into
    // the row when it turns on, and the row folds back into the text when off.
    _putMessage(joinCommitMessage(subject, _description.text));
    if (applied != null) _appliedTemplate = _message;
  }

  Future<void> _editTemplate() async {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final prefs = composerPrefsProvider(widget.repoPath);
    final controller = _templateEditor..text = ref.read(prefs).template;
    final saved = await showAppModal<String>(
      context: context,
      title: l.wtpTemplateTitle,
      icon: Icons.notes_outlined,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.wtpTemplateBody(_template?.commentChar ?? '#'),
            style: TextStyle(color: t.textMuted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 14,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12.5,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
            decoration: _dec(t, ''),
          ),
        ],
      ),
      actions: [
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: Text(l.wtpTemplateClear),
          ),
        ),
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
        ),
        Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l.save),
          ),
        ),
      ],
    );
    if (saved == null) return;
    await ref.read(prefs.notifier).update((p) => p.copyWith(template: saved));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final profile = ref.watch(profilesProvider).active;
    final skipHooks = ref.watch(skipHooksOnceProvider(widget.repoPath));
    final prefs = ref.watch(composerPrefsProvider(widget.repoPath));
    final length = subjectLength(_subject);
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
            if (prefs.conventional) ...[
              Row(
                children: [
                  DropdownButton<String>(
                    value: _type,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: t.bgElevated,
                    style: TextStyle(color: t.textPrimary, fontSize: 12.5),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(
                          l.wtpTypeNone,
                          style: TextStyle(color: t.textFaint),
                        ),
                      ),
                      for (final type in kConventionalTypes)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (v) {
                      setState(() => _type = v ?? '');
                      _edited();
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _scope,
                      style: TextStyle(color: t.textMuted, fontSize: 12.5),
                      decoration: _dec(t, l.wtpScopeHint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l.wtpBreakingTip,
                    child: _Toggle(
                      label: l.wtpBreaking,
                      value: _breaking,
                      onChanged: (v) {
                        setState(() => _breaking = v);
                        _edited();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _summary,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
              decoration: _dec(t, l.wtpSummary).copyWith(
                // A meter, not a rule: an over-long subject is still allowed.
                suffixText: '$length/${prefs.subjectLimit}',
                suffixStyle: TextStyle(
                  color: length > prefs.subjectLimit ? t.danger : t.textFaint,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              style: TextStyle(color: t.textMuted, fontSize: 12.5),
              maxLines: 3,
              minLines: 2,
              decoration: _dec(t, l.wtpDescription),
            ),
            if (_showTrailers) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _coauthors,
                style: TextStyle(color: t.textMuted, fontSize: 12),
                decoration: _dec(t, l.wtpCoauthorsHint),
              ),
              const SizedBox(height: 8),
              _IssueRefField(
                repoPath: widget.repoPath,
                controller: _refs,
                decoration: _dec(t, l.wtpRefsHint),
              ),
              const SizedBox(height: 8),
              _IssueRefField(
                repoPath: widget.repoPath,
                controller: _fixes,
                decoration: _dec(t, l.wtpFixesHint),
              ),
            ],
            const SizedBox(height: 8),
            if (skipHooks) ...[
              _SkipHooksStrip(repoPath: widget.repoPath),
              const SizedBox(height: 8),
            ],
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
                      _ComposerMenu(
                        prefs: prefs,
                        onConventional: _setConventional,
                        onLimit: (n) => ref
                            .read(
                              composerPrefsProvider(widget.repoPath).notifier,
                            )
                            .update((p) => p.copyWith(subjectLimit: n)),
                        onWrap: () => _description.text = wrapBody(
                          _description.text,
                          _wrapWidth,
                        ),
                        onTemplate: _editTemplate,
                      ),
                      _RecentMenu(
                        recent: _recent,
                        onSelected: (m) {
                          _putMessage(m);
                          _edited();
                        },
                      ),
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
                      Tooltip(
                        message: l.wtpSignoffTip,
                        child: _Toggle(
                          label: l.wtpSignoff,
                          value: _signoff,
                          onChanged: (v) => setState(() => _signoff = v),
                        ),
                      ),
                      _Toggle(
                        label: l.hkSkipHooks,
                        value: skipHooks,
                        onChanged: (v) =>
                            ref
                                    .read(
                                      skipHooksOnceProvider(widget.repoPath)
                                          .notifier,
                                    )
                                    .state =
                                v,
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _showTrailers = !_showTrailers),
                        child: Text(
                          l.wtpTrailers,
                          style: TextStyle(
                            color: _showTrailers ? t.accent : t.textFaint,
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

/// The composer's settings for this repository, plus the one-off action of
/// rewrapping the description.
class _ComposerMenu extends StatelessWidget {
  final ComposerPrefs prefs;
  final ValueChanged<bool> onConventional;
  final ValueChanged<int> onLimit;
  final VoidCallback onWrap;
  final VoidCallback onTemplate;
  const _ComposerMenu({
    required this.prefs,
    required this.onConventional,
    required this.onLimit,
    required this.onWrap,
    required this.onTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    const style = TextStyle(fontSize: 13);
    // Each entry carries its action and runs it from onSelected, once the
    // menu's route is gone — the template entry opens a dialog of its own.
    return PopupMenuButton<VoidCallback>(
      tooltip: l.wtpComposerMenu,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220),
      icon: Icon(Icons.tune, size: 15, color: t.textFaint),
      iconSize: 15,
      style: IconButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          checked: prefs.conventional,
          value: () => onConventional(!prefs.conventional),
          child: Text(l.wtpConventional, style: style),
        ),
        const PopupMenuDivider(),
        for (final n in _subjectLimits)
          CheckedPopupMenuItem(
            checked: prefs.subjectLimit == n,
            value: () => onLimit(n),
            child: Text(l.wtpSubjectLimit(n), style: style),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          height: 34,
          value: onWrap,
          child: Text(l.wtpWrapDescription(_wrapWidth), style: style),
        ),
        PopupMenuItem(
          height: 34,
          value: onTemplate,
          child: Text(l.wtpEditTemplate, style: style),
        ),
      ],
    );
  }
}

/// Messages recently committed from this repository, newest first, for
/// starting the next one from.
class _RecentMenu extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onSelected;
  const _RecentMenu({required this.recent, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return PopupMenuButton<String>(
      tooltip: l.wtpRecentMessages,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.history, size: 15, color: t.textFaint),
      iconSize: 15,
      style: IconButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelected: onSelected,
      itemBuilder: (_) => recent.isEmpty
          ? [
              PopupMenuItem(
                enabled: false,
                height: 34,
                child: Text(
                  l.wtpNoRecent,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]
          : [
              for (final m in recent)
                PopupMenuItem(
                  value: m,
                  height: 34,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      splitCommitMessage(m).summary,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
            ],
    );
  }
}

/// A comma-separated list of issue references that completes the entry
/// being typed from the forge's open issues, when the repository has a forge
/// set up. A reference typed by hand works the same either way.
class _IssueRefField extends ConsumerStatefulWidget {
  final String repoPath;
  final TextEditingController controller;
  final InputDecoration decoration;
  const _IssueRefField({
    required this.repoPath,
    required this.controller,
    required this.decoration,
  });

  @override
  ConsumerState<_IssueRefField> createState() => _IssueRefFieldState();
}

class _IssueRefFieldState extends ConsumerState<_IssueRefField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final issues =
        ref.watch(issuePanelProvider(widget.repoPath)).valueOrNull ??
        const <Issue>[];
    return RawAutocomplete<Issue>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final token = currentToken(value.text);
        return token.isEmpty ? const [] : matchIssues(issues, token).take(8);
      },
      displayStringForOption: (i) =>
          replaceCurrentToken(widget.controller.text, '#${i.number}'),
      fieldViewBuilder: (context, controller, focus, _) => TextField(
        controller: controller,
        focusNode: focus,
        style: TextStyle(color: t.textMuted, fontSize: 12),
        decoration: widget.decoration,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: t.bgElevated,
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 340),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final i in options)
                  InkWell(
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        '#${i.number} ${i.title}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary, fontSize: 12.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stays in view while the next commit is set to skip hooks, so the choice
/// cannot be forgotten between arming it and committing.
class _SkipHooksStrip extends ConsumerWidget {
  final String repoPath;
  const _SkipHooksStrip({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.hkSkipArmed,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: l.hkSkipDisarm,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: t.textMuted),
            onPressed: () =>
                ref.read(skipHooksOnceProvider(repoPath).notifier).state =
                    false,
          ),
        ],
      ),
    );
  }
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
