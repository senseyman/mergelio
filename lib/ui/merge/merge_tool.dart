import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/conflict.dart';
import '../../domain/git/diff.dart';
import '../../domain/git/models.dart';
import '../../domain/text_tabs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/binary_diff.dart';
import '../../state/merge_session.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/workspace.dart';
import '../diff/image_diff.dart';

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
  final _view = GlobalKey<_ConflictViewState>();

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

  /// Settles a conflict that has no hunks to pick between — a delete/modify
  /// pair, or binary content — by choosing what the path becomes.
  void _resolveFile(FileResolution r) {
    final session = _session;
    if (session == null) return;
    ref.read(mergeSessionProvider(widget.repoPath).notifier).state = session
        .replaceFile(_fileIndex, session.files[_fileIndex].withFileChoice(r));
  }

  /// True when a text field currently has focus, so the tool's shortcuts must
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
      // N jumps to the next unresolved file, ⌥↑/⌥↓ step through the open
      // file's conflicts — but not while the user is typing a custom
      // resolution into a hunk editor.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          if (_isEditingText()) return;
          if (!session.allResolved) _nextUnresolved(session);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () {
          if (!_isEditingText()) _view.currentState?.step(forward: false);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () {
          if (!_isEditingText()) _view.currentState?.step(forward: true);
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
                        key: _view,
                        repoPath: widget.repoPath,
                        file: file,
                        oursLabel: into == null
                            ? l.mtCurrent
                            : l.mtCurrentNamed(into),
                        theirsLabel: session.branch.isEmpty
                            ? l.mtIncoming
                            : l.mtIncomingNamed(session.branch),
                        onResolve: _resolve,
                        onResolveFile: _resolveFile,
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

class _ConflictView extends StatefulWidget {
  final String repoPath;
  final ConflictFile file;
  final String oursLabel;
  final String theirsLabel;
  final void Function(int hunk, Resolution r, {List<String>? lines}) onResolve;
  final ValueChanged<FileResolution> onResolveFile;
  const _ConflictView({
    super.key,
    required this.repoPath,
    required this.file,
    required this.oursLabel,
    required this.theirsLabel,
    required this.onResolve,
    required this.onResolveFile,
  });

  @override
  State<_ConflictView> createState() => _ConflictViewState();
}

class _ConflictViewState extends State<_ConflictView> {
  final _scroll = ScrollController();

  /// One key per part, by index, so a jump can find a hunk's card and the
  /// position bar can tell which part sits at the top of the view.
  final _partKeys = <int, GlobalKey>{};

  /// Which of the file's conflicts the reader is at, counted in file order:
  /// where the last jump landed, or the conflict at the top of the view after
  /// a hand scroll. Null until the user moves.
  int? _current;

  /// Jumps in flight. Their scrolling is not a hand scroll, so it must not
  /// overwrite the conflict the jump is heading for.
  int _jumps = 0;

  /// Bumped by every jump, so a newer one — a held-down key — takes over
  /// from any still searching.
  int _jumpGen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_ConflictView old) {
    super.didUpdateWidget(old);
    // Another file — or this one parsed afresh, with hunks that may have
    // moved or gone — starts with no conflict selected.
    if (old.file.path != widget.file.path ||
        !identical(old.file.parts, widget.file.parts)) {
      _current = null;
      _partKeys.clear();
    }
    if (old.file.path != widget.file.path && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Where part [i]'s top sits in scroll coordinates, and its height; null
  /// while the lazy list has not laid it out.
  (double, double)? _partSpan(int i) {
    final box = _partKeys[i]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    return (top, box.size.height);
  }

  void _onScroll() {
    if (_jumps > 0 || widget.file.wholeFile) return;
    final pixels = _scroll.position.pixels;
    int? atTop;
    for (var i = 0; i < widget.file.parts.length; i++) {
      final span = _partSpan(i);
      if (span != null && span.$1 + span.$2 > pixels) {
        atTop = i;
        break;
      }
    }
    if (atTop == null) return;
    final at = conflictAtPart(widget.file.hunkIndices, atTop);
    if (at != _current) setState(() => _current = at);
  }

  /// How tall part [i] is likely to be, in lines; hunk sides sit side by side
  /// under a header and a row of buttons.
  int _weight(int i) => switch (widget.file.parts[i]) {
    final ContextBlock b => b.lines.length,
    final ConflictHunk h =>
      (h.ours.length > h.theirs.length ? h.ours.length : h.theirs.length) + 6,
  };

  /// A guess at where part [target] starts, scaled from the parts the list
  /// has laid out — the one nearest the target anchors it.
  double _estimateTop(int target) {
    final pos = _scroll.position;
    var px = 0.0, weight = 0;
    int? anchor;
    for (var i = 0; i < widget.file.parts.length; i++) {
      final span = _partSpan(i);
      if (span == null) continue;
      px += span.$2;
      weight += _weight(i);
      if (anchor == null || (i - target).abs() < (anchor - target).abs()) {
        anchor = i;
      }
    }
    if (anchor == null || weight == 0) return pos.pixels;
    final perLine = px / weight;
    var top = _partSpan(anchor)!.$1;
    for (var i = anchor; i < target; i++) {
      top += _weight(i) * perLine;
    }
    for (var i = target; i < anchor; i++) {
      top -= _weight(i) * perLine;
    }
    return top.clamp(pos.minScrollExtent, pos.maxScrollExtent);
  }

  /// Scrolls part [part] to the top of the view. A lazy list only builds what
  /// is near the viewport, so a far-off hunk has no card yet: jump to where
  /// it should be, let a frame lay that stretch out, and look again — each
  /// pass measures more of the file, so the guess tightens.
  Future<void> _reveal(int part) async {
    final gen = ++_jumpGen;
    _jumps++;
    try {
      for (var pass = 0; pass < 12; pass++) {
        // Measure after this frame's rebuild, not before it.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients || gen != _jumpGen) return;
        final ctx = _partKeys[part]?.currentContext;
        if (ctx != null) {
          if (!ctx.mounted) return;
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
          return;
        }
        _scroll.jumpTo(_estimateTop(part));
      }
    } finally {
      _jumps--;
    }
  }

  /// Scrolls the next (or previous) conflict to the top of the view.
  void step({required bool forward}) {
    if (widget.file.wholeFile) return;
    final hunks = widget.file.hunkIndices;
    final target = stepConflict(hunks.length, _current, forward: forward);
    if (target == null) return;
    setState(() => _current = target);
    _reveal(hunks[target]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final file = widget.file;
    final repoPath = widget.repoPath;
    final oursLabel = widget.oursLabel;
    final theirsLabel = widget.theirsLabel;
    final onResolve = widget.onResolve;
    final onResolveFile = widget.onResolveFile;
    if (file.wholeFile) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _WholeFileCard(
            repoPath: repoPath,
            file: file,
            oursLabel: oursLabel,
            theirsLabel: theirsLabel,
            onChoose: onResolveFile,
          ),
        ],
      );
    }
    final total = file.hunkIndices.length;
    final current = _current;
    final body = ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: file.parts.length,
      itemBuilder: (context, i) => KeyedSubtree(
        key: _partKeys.putIfAbsent(i, GlobalKey.new),
        child: switch (file.parts[i]) {
          final ConflictHunk hunk => _HunkCard(
            key: ValueKey('$i'),
            hunk: hunk,
            oursLabel: oursLabel,
            theirsLabel: theirsLabel,
            resolution: file.resolutions[i],
            custom: file.custom[i],
            onAccept: (r, {lines}) => onResolve(i, r, lines: lines),
          ),
          final ContextBlock block
              when block.lines.any((l) => l.trim().isNotEmpty) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                expandTabs(block.lines.join('\n')),
                style: AppFonts.mns(size: 12.5, color: t.textFaint),
              ),
            ),
          ContextBlock() => const SizedBox.shrink(),
        },
      ),
    );
    if (total == 0) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.bgPanel,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Expanded(
                // Announced as it changes, so a screen reader hears where a
                // jump landed.
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    current == null
                        ? l.mtConflictCount(total)
                        : l.mtConflictPosition(current + 1, total),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                ),
              ),
              IconButton(
                tooltip: l.mtPrevConflict,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => step(forward: false),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: l.mtNextConflict,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => step(forward: true),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// A conflict git left without markers: binary content, or a path one side
/// deleted. There is nothing to merge line by line, so the whole file is
/// settled with one choice — and a side that deleted the path is not offered,
/// since it has no content to keep.
class _WholeFileCard extends StatelessWidget {
  final String repoPath;
  final ConflictFile file;
  final String oursLabel;
  final String theirsLabel;
  final ValueChanged<FileResolution> onChoose;
  const _WholeFileCard({
    required this.repoPath,
    required this.file,
    required this.oursLabel,
    required this.theirsLabel,
    required this.onChoose,
  });

  /// Why there is nothing to merge line by line. Which side did what comes
  /// first: it is the more specific fact, and the one that explains why a
  /// choice may be missing.
  String _reason(AppLocalizations l) => switch (file.kind) {
    ConflictKind.deletedByUs => l.mtDeletedByUs,
    ConflictKind.deletedByThem => l.mtDeletedByThem,
    ConflictKind.addedByUs => l.mtAddedByUs,
    ConflictKind.addedByThem => l.mtAddedByThem,
    ConflictKind.bothDeleted => l.mtBothDeleted,
    _ => file.submodule ? l.mtSubmoduleConflict : l.mtBinaryConflict,
  };

  String _label(AppLocalizations l, FileResolution r) => switch (r) {
    FileResolution.ours => l.mtKeepMine,
    FileResolution.theirs => l.mtKeepTheirs,
    FileResolution.delete => l.mtDeleteFile,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final chosen = file.fileChoice;
    return Card(
      color: t.bgPanel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    file.path,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.mns(size: 12.5, color: t.textPrimary),
                  ),
                ),
                if (chosen != null)
                  Text(
                    l.mtResolved,
                    style: TextStyle(color: t.success, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _reason(l),
              style: TextStyle(color: t.textMuted, fontSize: 12.5),
            ),
            // Binary content cannot be read as text, so each side is shown
            // as itself to choose between.
            if (file.binary) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 300,
                child: BinaryCompare(
                  repoPath: repoPath,
                  sides: conflictSidesFor(
                    file.path,
                    hasOurs: file.kind.hasOurs,
                    hasTheirs: file.kind.hasTheirs,
                  ),
                  beforeLabel: oursLabel,
                  afterLabel: theirsLabel,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in file.fileOptions)
                  if (r == chosen)
                    FilledButton(
                      onPressed: () => onChoose(r),
                      child: Text(_label(l, r)),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => onChoose(r),
                      child: Text(_label(l, r)),
                    ),
              ],
            ),
          ],
        ),
      ),
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
                    style: AppFonts.mns(size: 11, color: t.textFaint),
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
                      style: AppFonts.mns(size: 12.5, color: t.textPrimary),
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
                  expandTabs(
                    resolveConflicts(
                      [hunk],
                      {0: res},
                      custom: {0: widget.custom ?? const []},
                    ).trimRight(),
                  ),
                  style: AppFonts.mns(size: 12.5, color: t.textMuted),
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
    final base = AppFonts.mns(size: 12.5);
    if (against == null || against == line) {
      return TextSpan(
        text: expandTabs(line),
        style: base.copyWith(color: t.textMuted),
      );
    }
    // A tab advances to the next stop from wherever it sits, so the column has
    // to run across the joins between the segments.
    var column = 0;
    String expand(String text) {
      final r = expandTabsFrom(text, column);
      column = r.column;
      return r.text;
    }

    // diffWords(against, line): the second side's changed segments.
    final (_, segs) = diffWords(against, line);
    return TextSpan(
      children: [
        for (final s in segs)
          TextSpan(
            text: expand(s.text),
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
