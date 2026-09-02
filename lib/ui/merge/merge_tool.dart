import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/conflict.dart';
import '../../domain/git/diff.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/merge_session.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/workspace.dart';

/// Full-panel conflict resolver shown while a [MergeSession] is active. Lists
/// conflicted files, shows each conflict's ours/theirs with Accept buttons and
/// a live RESULT preview, and gates Finish until everything is resolved.
class MergeTool extends ConsumerStatefulWidget {
  final String repoPath;
  const MergeTool({super.key, required this.repoPath});

  @override
  ConsumerState<MergeTool> createState() => _MergeToolState();
}

class _MergeToolState extends ConsumerState<MergeTool> {
  int _fileIndex = 0;

  MergeSession? get _session => ref.read(mergeSessionProvider(widget.repoPath));

  void _resolve(int hunk, Resolution r, {List<String>? lines}) {
    final session = _session;
    if (session == null) return;
    final file = session.files[_fileIndex].withResolution(
      hunk,
      r,
      lines: lines,
    );
    ref.read(mergeSessionProvider(widget.repoPath).notifier).state = session
        .replaceFile(_fileIndex, file);
  }

  /// True when a text field currently has focus, so letter shortcuts (N) must
  /// not fire — they'd be swallowed keystrokes in the hunk editor.
  bool _isEditingText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Selects the next file with unresolved conflicts (wraps around).
  void _nextUnresolved(MergeSession session) {
    for (var i = 1; i <= session.files.length; i++) {
      final idx = (_fileIndex + i) % session.files.length;
      if (!session.files[idx].resolved) {
        setState(() => _fileIndex = idx);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final session = ref.watch(mergeSessionProvider(widget.repoPath));
    if (session == null) return const SizedBox.shrink();
    final actions = ref.read(repoActionsProvider(widget.repoPath));
    if (_fileIndex >= session.files.length) _fileIndex = 0;
    final file = session.files[_fileIndex];
    // The branch being merged into — the current branch.
    final into = ref
        .watch(repoDataProvider(widget.repoPath))
        .valueOrNull
        ?.branches
        .where((b) => b.current)
        .firstOrNull
        ?.name;

    return CallbackShortcuts(
      // N jumps to the next unresolved conflict — but not while the user is
      // typing a custom resolution into a hunk editor.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          if (_isEditingText()) return;
          if (!session.allResolved) _nextUnresolved(session);
        },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: t.bgApp,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                kind: session.kind,
                branch: session.branch,
                into: into,
                resolved: session.resolvedConflicts,
                total: session.totalConflicts,
                canFinish: session.allResolved,
                onNext: session.allResolved
                    ? null
                    : () => _nextUnresolved(session),
                onAbort: actions.abortMerge,
                onResolve: () => actions.resolveConflicts(session),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FileList(
                      files: session.files,
                      active: _fileIndex,
                      onSelect: (i) => setState(() => _fileIndex = i),
                    ),
                    Container(width: 1, color: t.border),
                    Expanded(
                      child: _ConflictView(
                        file: file,
                        oursLabel: into == null
                            ? l.mtCurrent
                            : l.mtCurrentNamed(into),
                        theirsLabel: session.branch.isEmpty
                            ? l.mtIncoming
                            : l.mtIncomingNamed(session.branch),
                        onResolve: _resolve,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MergeKind kind;
  final String branch;
  final String? into;
  final int resolved;
  final int total;
  final bool canFinish;
  final VoidCallback? onNext;
  final VoidCallback onAbort;
  final VoidCallback onResolve;
  const _Header({
    required this.kind,
    required this.branch,
    required this.into,
    required this.resolved,
    required this.total,
    required this.canFinish,
    required this.onNext,
    required this.onAbort,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: t.warning),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              switch (kind) {
                MergeKind.stash => l.mergeResolveConflicts,
                MergeKind.rebase => l.mergeRebase,
                MergeKind.cherryPick => l.mergeCherryPick(branch),
                MergeKind.revert => l.mergeRevert(branch),
                MergeKind.merge =>
                  into == null
                      ? l.mergeBranch(branch)
                      : l.mergeInto(branch, into!),
              },
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Both texts give way before the buttons do: at the minimum window
          // width the title and the count together are wider than the row.
          Flexible(
            child: Text(
              l.mergeResolvedCount(resolved, total),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textFaint, fontSize: 12),
            ),
          ),
          const Spacer(),
          TextButton(onPressed: onNext, child: Text(l.mergeNextUnresolved)),
          const SizedBox(width: 8),
          TextButton(onPressed: onAbort, child: Text(l.mergeAbort)),
          const SizedBox(width: 8),
          // Resolving stages the result and stops there — committing it, or
          // continuing the sequence, is the user's next move in the panel.
          FilledButton(
            onPressed: canFinish ? onResolve : null,
            child: Text(l.mergeResolve),
          ),
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  final List<ConflictFile> files;
  final int active;
  final ValueChanged<int> onSelect;
  const _FileList({
    required this.files,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 240,
      child: ListView(
        children: [
          for (var i = 0; i < files.length; i++)
            InkWell(
              onTap: () => onSelect(i),
              child: Container(
                color: i == active ? t.active : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      files[i].resolved
                          ? Icons.check_circle
                          : Icons.error_outline,
                      size: 14,
                      color: files[i].resolved ? t.success : t.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        files[i].path,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textMuted, fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${files[i].resolvedCount}/${files[i].total}',
                      style: TextStyle(color: t.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConflictView extends StatelessWidget {
  final ConflictFile file;
  final String oursLabel;
  final String theirsLabel;
  final void Function(int hunk, Resolution r, {List<String>? lines}) onResolve;
  const _ConflictView({
    required this.file,
    required this.oursLabel,
    required this.theirsLabel,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < file.parts.length; i++)
          if (file.parts[i] case final ConflictHunk hunk)
            _HunkCard(
              key: ValueKey('$i'),
              hunk: hunk,
              oursLabel: oursLabel,
              theirsLabel: theirsLabel,
              resolution: file.resolutions[i],
              custom: file.custom[i],
              onAccept: (r, {lines}) => onResolve(i, r, lines: lines),
            )
          else if (file.parts[i] case final ContextBlock block)
            if (block.lines.any((l) => l.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  block.lines.join('\n'),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
      ],
    );
  }
}

class _HunkCard extends StatefulWidget {
  final ConflictHunk hunk;
  final String oursLabel;
  final String theirsLabel;
  final Resolution? resolution;
  final List<String>? custom;
  final void Function(Resolution r, {List<String>? lines}) onAccept;
  const _HunkCard({
    super.key,
    required this.hunk,
    required this.oursLabel,
    required this.theirsLabel,
    required this.resolution,
    required this.custom,
    required this.onAccept,
  });

  @override
  State<_HunkCard> createState() => _HunkCardState();
}

class _HunkCardState extends State<_HunkCard> {
  TextEditingController? _editor;

  void _startEdit() {
    final seed = (widget.custom ?? [...widget.hunk.ours, ...widget.hunk.theirs])
        .join('\n');
    setState(() => _editor = TextEditingController(text: seed));
  }

  @override
  void dispose() {
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final hunk = widget.hunk;
    final res = widget.resolution;

    return Card(
      color: t.bgPanel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hunk header: original file position + resolution state badge.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
              child: Row(
                children: [
                  Text(
                    '@@ line ${hunk.line} @@',
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  if (res == Resolution.both)
                    Text(
                      l.mtNeedsReview,
                      style: TextStyle(color: t.warning, fontSize: 11),
                    )
                  else if (res != null)
                    Text(
                      l.mtResolved,
                      style: TextStyle(color: t.success, fontSize: 11),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current side carries the success tint, incoming the accent,
                // matching the spec's zone colours.
                _side(
                  l,
                  t,
                  widget.oursLabel,
                  hunk.ours,
                  hunk.theirs,
                  t.addWord,
                  t.success,
                  Resolution.ours,
                ),
                _side(
                  l,
                  t,
                  widget.theirsLabel,
                  hunk.theirs,
                  hunk.ours,
                  t.delWord,
                  t.accent,
                  Resolution.theirs,
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => widget.onAccept(Resolution.both),
                  child: Text(
                    res == Resolution.both ? l.mtBothAccepted : l.mtAcceptBoth,
                    style: TextStyle(
                      fontSize: 12,
                      color: res == Resolution.both ? t.warning : t.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _editor == null ? _startEdit : null,
                  child: Text(l.edit, style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (_editor != null)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _editor,
                      maxLines: null,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        labelText: l.mtResult,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => widget.onAccept(
                          Resolution.custom,
                          lines: _editor!.text.split('\n'),
                        ),
                        child: Text(
                          l.mtUseEdit,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (res != null)
              // Live RESULT preview of the current resolution.
              Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.bgApp,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  resolveConflicts(
                    [hunk],
                    {0: res},
                    custom: {0: widget.custom ?? const []},
                  ).trimRight(),
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One side (OURS/THEIRS) with word-level highlight against [other].
  Widget _side(
    AppLocalizations l,
    AppTokens t,
    String label,
    List<String> lines,
    List<String> other,
    Color wordBg,
    Color color,
    Resolution r,
  ) => Expanded(
    child: Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: widget.resolution == r ? color : t.border,
          width: widget.resolution == r ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => widget.onAccept(r),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                  child: Text(l.mtAccept, style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: lines.isEmpty
                ? Text(
                    '(empty)',
                    style: TextStyle(color: t.textFaint, fontSize: 12.5),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Text.rich(
                          _lineSpans(
                            t,
                            lines[i],
                            i < other.length ? other[i] : null,
                            wordBg,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  /// Highlights the tokens of [line] that differ from [against] (its opposite-
  /// side counterpart), so the changed part of a modified line stands out.
  TextSpan _lineSpans(AppTokens t, String line, String? against, Color bg) {
    const base = TextStyle(fontSize: 12.5, fontFamily: 'monospace');
    if (against == null || against == line) {
      return TextSpan(
        text: line,
        style: base.copyWith(color: t.textMuted),
      );
    }
    // diffWords(against, line): the second side's changed segments.
    final (_, segs) = diffWords(against, line);
    return TextSpan(
      children: [
        for (final s in segs)
          TextSpan(
            text: s.text,
            style: base.copyWith(
              color: t.textPrimary,
              backgroundColor: s.changed ? bg : null,
            ),
          ),
      ],
    );
  }
}

/// Shows the Merge Tool over the whole workspace body while a merge is active.
class MergeToolGate extends ConsumerWidget {
  final Widget child;
  const MergeToolGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final active =
        path != null && ref.watch(mergeSessionProvider(path)) != null;
    if (!active) return child;
    return MergeTool(repoPath: path);
  }
}
