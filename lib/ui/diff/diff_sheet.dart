import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/diff.dart';
import '../../domain/git/models.dart';
import '../../domain/git/stage_patch.dart';
import '../../state/diff_document.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/file_editor.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../common/confirm.dart';
import 'diff_editor.dart';
import 'diff_metrics.dart';
import 'diff_selection.dart';
import 'line_selection.dart';
import 'linked_scroll.dart';
import 'syntax_style.dart';
import '../../l10n/gen/app_localizations.dart';

/// Slide-up diff sheet over the graph. Occupies [settings.diffHeight] of the
/// available height; the grip resizes it. Renders inline/split with word-level
/// and syntax highlighting, and — for the working tree — a staging gutter.
class DiffSheet extends ConsumerWidget {
  final double availableHeight;
  const DiffSheet({super.key, required this.availableHeight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(diffTargetProvider);
    if (target == null) return const SizedBox.shrink();
    final t = context.tokens;
    final frac = ref.watch(settingsProvider.select((s) => s.diffHeight));
    final ctl = ref.read(settingsProvider.notifier);
    final height = availableHeight * frac;
    final editing = ref.watch(diffEditingProvider) == target;

    Future<void> close() async {
      final l = AppLocalizations.of(context);
      // Closing the sheet mid-edit would drop the typed text without a word.
      if (editing && ref.read(diffEditorDirtyProvider)) {
        final ok = await confirmDestructive(
          ref,
          context,
          title: l.diffDiscardEditsTitle,
          body:
              'What you typed in ${target.path} has not been written to the '
              'working tree.',
          confirmLabel: l.discard,
        );
        if (!ok) return;
      }
      ref.read(diffEditorDirtyProvider.notifier).state = false;
      ref.read(diffEditingProvider.notifier).state = null;
      ref.read(diffTargetProvider.notifier).state = null;
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          // While editing, Escape belongs to the editor (cancel), not to the
          // sheet — closing out from under unsaved text would lose it.
          if (editing) return KeyEventResult.ignored;
          close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: t.bgPanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _Grip(
              onDrag: (dy) => ctl.setDiffHeight(frac - dy / availableHeight),
            ),
            _DiffHeader(target: target, onClose: close),
            Expanded(
              child: editing
                  ? DiffEditor(target: target)
                  : _DiffBody(target: target),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  final void Function(double dy) onDrag;
  const _Grip({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 14,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: t.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header buttons share a 38px bar with the path, the toggles and the close
/// button, so they use tighter padding than the Material default.
final _compactButton = TextButton.styleFrom(
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

class _DiffHeader extends ConsumerWidget {
  final DiffTarget target;
  final VoidCallback onClose;
  const _DiffHeader({required this.target, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final split = ref.watch(settingsProvider.select((s) => s.diffSplit));
    final ctl = ref.read(settingsProvider.notifier);
    final doc = ref.watch(diffDocumentProvider(target)).valueOrNull;
    final editing = ref.watch(diffEditingProvider) == target;
    // Partial working-tree file: let the user flip between the two sides.
    final working =
        ref.watch(repoDataProvider(target.repoPath)).valueOrNull?.working ??
        const <WorkingFile>[];
    WorkingFile? wf;
    for (final f in working) {
      if (f.path == target.path) {
        wf = f;
        break;
      }
    }
    final partial = target.commitSha == null && (wf?.isPartial ?? false);
    final context0 = target.commitSha != null
        ? 'commit ${target.commitSha!.length > 7 ? target.commitSha!.substring(0, 7) : target.commitSha}'
        : 'Uncommitted changes · working tree';

    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          _StatusBadge(target: target),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              target.path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context0,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textFaint, fontSize: 11),
            ),
          ),
          const Spacer(),
          if (partial) ...[
            _SideToggle(
              staged: target.staged,
              onUnstaged: () => ref.read(diffTargetProvider.notifier).state =
                  target.withStaged(false),
              onStaged: () => ref.read(diffTargetProvider.notifier).state =
                  target.withStaged(true),
            ),
            const SizedBox(width: 8),
          ],
          if (target.isWorkingTree && !editing)
            TextButton(
              style: _compactButton,
              onPressed: () =>
                  ref.read(diffEditingProvider.notifier).state = target,
              child: Text(l.edit),
            ),
          if (doc != null && doc.editable && !editing)
            TextButton(
              style: _compactButton,
              onPressed: () async {
                final actions = ref.read(repoActionsProvider(target.repoPath));
                if (doc.staged) {
                  await actions.unstageFile(target.path);
                } else {
                  await actions.stageFile(target.path);
                }
                ref.invalidate(diffDocumentProvider(target));
              },
              child: Text(doc.staged ? 'Unstage file' : 'Stage file'),
            ),
          _SegToggle(
            split: split,
            onInline: () => ctl.setDiffSplit(false),
            onSplit: () => ctl.setDiffSplit(true),
          ),
          if (!editing)
            IconButton(
              iconSize: 18,
              tooltip: target.wholeFile
                  ? 'Show changes only'
                  : 'Show whole file',
              icon: Icon(
                target.wholeFile ? Icons.unfold_less : Icons.unfold_more,
              ),
              onPressed: () => ref.read(diffTargetProvider.notifier).state =
                  target.withWholeFile(!target.wholeFile),
            ),
          IconButton(
            iconSize: 18,
            tooltip: l.close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// M/A/D/R status letter for the file being diffed, sourced from the working
/// tree (working diffs) or the commit's change list (commit diffs).
class _StatusBadge extends ConsumerWidget {
  final DiffTarget target;
  const _StatusBadge({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    GitChange? change;
    if (target.commitSha == null) {
      final files =
          ref.watch(repoDataProvider(target.repoPath)).valueOrNull?.working ??
          const <WorkingFile>[];
      for (final f in files) {
        if (f.path == target.path) {
          change = f.worktree != GitChange.none ? f.worktree : f.index;
          break;
        }
      }
    } else {
      final files = ref
          .watch(
            commitFilesProvider((
              repo: target.repoPath,
              sha: target.commitSha!,
            )),
          )
          .valueOrNull;
      for (final f in files ?? const <CommitFileChange>[]) {
        if (f.path == target.path) {
          change = f.change;
          break;
        }
      }
    }
    if (change == null) return const SizedBox.shrink();
    final (color, letter) = switch (change) {
      GitChange.added || GitChange.untracked => (t.success, 'A'),
      GitChange.deleted => (t.danger, 'D'),
      GitChange.renamed => (t.accent, 'R'),
      GitChange.copied => (t.accent, 'C'),
      _ => (t.warning, 'M'),
    };
    return Container(
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
    );
  }
}

class _SegToggle extends StatelessWidget {
  final bool split;
  final VoidCallback onInline;
  final VoidCallback onSplit;
  const _SegToggle({
    required this.split,
    required this.onInline,
    required this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget seg(String label, bool on, VoidCallback tap) => InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: on ? t.active : null,
        child: Text(
          label,
          style: TextStyle(
            color: on ? t.textPrimary : t.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Inline', !split, onInline),
          seg('Split', split, onSplit),
        ],
      ),
    );
  }
}

class _DiffBody extends ConsumerStatefulWidget {
  final DiffTarget target;
  const _DiffBody({required this.target});

  @override
  ConsumerState<_DiffBody> createState() => _DiffBodyState();
}

class _DiffBodyState extends ConsumerState<_DiffBody> {
  // Owned by the body rather than by a row: one controller drives every line,
  // so the columns cannot drift apart as the diff scrolls sideways.
  final _hInline = ScrollController();

  // Split view gives each column its own horizontal scroll — the two sides
  // rarely hold lines of the same length, and a new file has nothing at all on
  // the left, which under one shared width crowded the additions off-screen.
  // Vertically they stay a single surface, so one linked controller drives
  // both lists.
  final _hLeft = ScrollController();
  final _hRight = ScrollController();
  final _vSplit = LinkedScrollController();

  @override
  void dispose() {
    _hInline.dispose();
    _hLeft.dispose();
    _hRight.dispose();
    _vSplit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final target = widget.target;
    final t = context.tokens;
    final split = ref.watch(settingsProvider.select((s) => s.diffSplit));
    // Watched rather than read on demand: whether the file is tracked decides
    // how discarding works, and a snapshot taken before the repository has
    // loaded would report it as tracked.
    final working =
        ref.watch(repoDataProvider(target.repoPath)).valueOrNull?.working ??
        const <WorkingFile>[];
    // Line indices mean nothing once the sheet moves to another file or the
    // other staging side, so a run picked out there must not survive.
    ref.listen(diffTargetProvider, (_, _) {
      ref.read(lineSelectionProvider.notifier).state = null;
    });
    return ref
        .watch(diffDocumentProvider(target))
        .when(
          loading: () => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (e, _) => Center(
            child: Text(
              'Could not load diff',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ),
          data: (doc) {
            if (doc.isBinary) {
              return Center(
                child: Text(
                  'Binary file — diff not shown',
                  style: TextStyle(color: t.textFaint, fontSize: 12),
                ),
              );
            }
            if (doc.isEmpty) {
              return Center(
                child: Text(
                  'No changes',
                  style: TextStyle(color: t.textFaint, fontSize: 12),
                ),
              );
            }
            final items = _flatten(doc.files, split);
            Future<void> apply(
              FileDiff file,
              int hunkIndex,
              Set<int>? lineIndexes,
            ) async {
              final patch = buildStagePatch(
                file,
                hunkIndex,
                lineIndexes: lineIndexes,
              );
              if (patch == null) return;
              try {
                await ref
                    .read(repoActionsProvider(target.repoPath))
                    .applyPatch(patch, reverse: doc.staged);
                ref.invalidate(diffDocumentProvider(target));
              } on Object catch (e) {
                ref
                    .read(toastProvider.notifier)
                    .show(
                      doc.staged ? 'Could not unstage' : 'Could not stage',
                      description: '$e',
                      kind: ToastKind.error,
                    );
              }
            }

            /// The working-tree entry for [path] when git is not tracking it,
            /// null otherwise — discarding differs for the two.
            WorkingFile? untrackedFile(String path) {
              for (final f in working) {
                if (f.path == path && f.isUntracked) return f;
              }
              return null;
            }

            Future<void> discard(
              FileDiff file,
              int hunkIndex, [
              Set<int>? lineIndexes,
            ]) async {
              // An untracked file has no committed state to revert to, so
              // reversing its patch would only empty it and leave the file
              // behind. Taking back all of it means deleting it instead.
              final wf = untrackedFile(file.path);
              if (wf != null && lineIndexes == null && file.hunks.length == 1) {
                final ok = await confirmDestructive(
                  ref,
                  context,
                  title: l.diffDiscardFileTitle(file.path),
                  body: l.diffDiscardFileBody,
                  confirmLabel: l.discard,
                );
                if (!ok) return;
                await ref
                    .read(repoActionsProvider(target.repoPath))
                    .discardFile(wf);
                ref.invalidate(diffDocumentProvider(target));
                return;
              }

              // Discarding reverse-applies to the working tree, which holds
              // every change in the hunk — not the staging patch, whose
              // post-image leaves the untouched ones out and would not match.
              final patch = buildDiscardPatch(file, hunkIndex, lineIndexes);
              if (patch == null) return;
              final ok = await confirmDestructive(
                ref,
                context,
                title: lineIndexes == null
                    ? 'Discard hunk?'
                    : 'Discard ${lineIndexes.length} '
                          '${lineIndexes.length == 1 ? 'line' : 'lines'}?',
                body:
                    'This removes the selected changes from the working tree. '
                    'You can undo it.',
                confirmLabel: l.discard,
              );
              if (!ok) return;
              try {
                await ref
                    .read(repoActionsProvider(target.repoPath))
                    .discardHunk(patch);
                ref.invalidate(diffDocumentProvider(target));
              } on Object catch (e) {
                ref
                    .read(toastProvider.notifier)
                    .show(
                      'Could not discard',
                      description: '$e',
                      kind: ToastKind.error,
                    );
              }
            }

            // Staging a picked-out run reuses the per-hunk patch builder: the
            // selection is confined to one hunk, so its line indices address
            // that hunk directly.
            (FileDiff, DiffLineSelection)? selectedRun() {
              final sel = ref.read(lineSelectionProvider);
              if (sel == null) return null;
              for (final f in doc.files) {
                if (f.path == sel.path && sel.hunkIndex < f.hunks.length) {
                  return (f, sel);
                }
              }
              return null;
            }

            void clearRun() =>
                ref.read(lineSelectionProvider.notifier).state = null;

            Future<void> applyRun() async {
              final run = selectedRun();
              if (run == null) return;
              await apply(run.$1, run.$2.hunkIndex, run.$2.lines);
              clearRun();
            }

            Future<void> discardRun() async {
              final run = selectedRun();
              if (run == null) return;
              await discard(run.$1, run.$2.hunkIndex, run.$2.lines);
              clearRun();
            }

            void openMenu(BuildContext menuContext, Offset at) {
              final hasRun = selectedRun() != null;
              showDiffSelectionMenu(
                menuContext,
                at,
                stageLabel: doc.staged
                    ? 'Unstage selected lines'
                    : 'Stage selected lines',
                onStageLines: hasRun && doc.editable ? applyRun : null,
                onDiscardLines: hasRun && doc.editable && !doc.staged
                    ? discardRun
                    : null,
              );
            }

            /// Ends a line-selection drag wherever the pointer is released,
            /// including outside the row it started on.
            Widget endDragOnRelease(Widget child) => Listener(
              onPointerUp: (_) =>
                  ref.read(lineDraggingProvider.notifier).state = false,
              child: child,
            );

            Widget headerRow(
              _DiffItem it, {
              bool showActions = true,
              bool showMarker = true,
            }) => _HunkHeaderRow(
              // The whole-file view collapses everything into one hunk, so
              // a "stage hunk" there would silently act on the entire file.
              // Line-level staging still applies.
              header: it.file.hunks[it.hunkIndex].header,
              editable: doc.editable && !target.wholeFile,
              staged: doc.staged,
              onStage: () => apply(it.file, it.hunkIndex, null),
              onDiscard: doc.staged || target.wholeFile
                  ? null
                  : () => discard(it.file, it.hunkIndex),
              showActions: showActions,
              showMarker: showMarker,
            );

            if (split) {
              final sides = longestLineCharsPerSide(doc.files);
              final charWidth = _codeCharWidth(context);
              final lineHeight = _codeLineHeight(context);
              return endDragOnRelease(
                Row(
                  children: [
                    Expanded(
                      child: _SplitColumn(
                        items: items,
                        onMenu: openMenu,
                        isLeft: true,
                        chars: sides.left,
                        charWidth: charWidth,
                        lineHeight: lineHeight,
                        hController: _hLeft,
                        vController: _vSplit,
                        header: headerRow,
                      ),
                    ),
                    Expanded(
                      child: _SplitColumn(
                        items: items,
                        onMenu: openMenu,
                        isLeft: false,
                        chars: sides.right,
                        charWidth: charWidth,
                        lineHeight: lineHeight,
                        hController: _hRight,
                        vController: _vSplit,
                        header: headerRow,
                      ),
                    ),
                  ],
                ),
              );
            }

            // ListView.builder virtualises: only visible rows build (and only
            // they run highlightLine), so large diffs and grip-resize stay
            // smooth.
            //
            // SelectionArea makes the code text selectable and copyable. Every
            // part of a row that is not code — gutter, line numbers, +/- sign,
            // hunk header — opts out via SelectionContainer.disabled, so a copy
            // yields source, not source interleaved with line numbers.
            // Code lines are laid out with softWrap off, so anything past the
            // right edge would otherwise be clipped with no way to reach it.
            // The list is given the width of its longest line and the whole
            // thing scrolls sideways, gutter included.
            //
            // The scroll view sits outside SelectionArea on purpose: a
            // viewport between the region and its selectables leaves
            // selectAll() with nothing to select.
            return endDragOnRelease(
              LayoutBuilder(
                builder: (context, constraints) => Scrollbar(
                  controller: _hInline,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _hInline,
                    child: SizedBox(
                      width: diffContentWidth(
                        viewport: constraints.maxWidth,
                        chars: longestLineChars(doc.files),
                        charWidth: _codeCharWidth(context),
                      ),
                      child: SelectionArea(
                        // The built-in toolbar is replaced by
                        // showDiffSelectionMenu, which also opens where nothing
                        // is selected yet. It is suppressed with an empty builder
                        // rather than a null one: SelectableRegion._showToolbar
                        // dereferences the builder with `!`, so null crashes the
                        // frame instead of hiding the toolbar.
                        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                        child: Builder(
                          builder: (context) => GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onSecondaryTapUp: (d) =>
                                openMenu(context, d.globalPosition),
                            child: ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final it = items[i];
                                final hunk = it.file.hunks[it.hunkIndex];
                                if (it.header) {
                                  return _PinnedToViewport(
                                    controller: _hInline,
                                    viewport: constraints.maxWidth,
                                    child: headerRow(it),
                                  );
                                }
                                final li = it.lineIndex!;
                                final line = hunk.lines[li];
                                return _LineRow(
                                  line: line,
                                  path: it.file.path,
                                  hunkIndex: it.hunkIndex,
                                  lineIndex: li,
                                  editable: doc.editable,
                                  staged: doc.staged,
                                  onStage: line.type == DiffLineType.context
                                      ? null
                                      : () => apply(
                                          it.file,
                                          it.hunkIndex,
                                          changeLineGroup(hunk.lines, li),
                                        ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
  }
}

const _codeStyle = TextStyle(
  fontSize: 12.5,
  fontFamily: 'monospace',
  height: 1.35,
);

TextPainter _codeMetrics(BuildContext context) => TextPainter(
  text: const TextSpan(text: 'M', style: _codeStyle),
  textDirection: TextDirection.ltr,
  textScaler: MediaQuery.textScalerOf(context),
)..layout();

/// Width of one character in the code font, so the widest line can be sized
/// without laying every line out. The font is monospace, so any glyph will do.
double _codeCharWidth(BuildContext context) => _codeMetrics(context).width;

/// Height of one code line, used to give both split columns rows of the same
/// height so they stay aligned while scrolling as one.
double _codeLineHeight(BuildContext context) => _codeMetrics(context).height;

/// One virtualised row of the diff body: a hunk header, an inline line, or a
/// split pair.
class _DiffItem {
  final FileDiff file;
  final int hunkIndex;
  final bool header;
  final int? lineIndex;
  final (int?, int?)? pair;
  const _DiffItem({
    required this.file,
    required this.hunkIndex,
    this.header = false,
    this.lineIndex,
    this.pair,
  });
}

List<_DiffItem> _flatten(List<FileDiff> files, bool split) {
  final items = <_DiffItem>[];
  for (final f in files) {
    for (var hi = 0; hi < f.hunks.length; hi++) {
      items.add(_DiffItem(file: f, hunkIndex: hi, header: true));
      if (split) {
        for (final pair in _pairForSplit(f.hunks[hi].lines)) {
          items.add(_DiffItem(file: f, hunkIndex: hi, pair: pair));
        }
      } else {
        for (var li = 0; li < f.hunks[hi].lines.length; li++) {
          items.add(_DiffItem(file: f, hunkIndex: hi, lineIndex: li));
        }
      }
    }
  }
  return items;
}

/// Height of a hunk header. Fixed so the two split columns — one carrying the
/// marker, the other the buttons — keep the same rows at the same heights.
const _hunkHeaderHeight = 22.0;

/// Holds a hunk header still while the code beneath it scrolls sideways.
///
/// The header lives inside the horizontally scrolling content, which is as
/// wide as the longest line, so its right-aligned buttons would otherwise sit
/// at the far end of that width — off screen until you scrolled to the end of
/// the longest line in the hunk. Sizing it to the viewport and shifting it by
/// the current offset pins it to the visible area instead.
class _PinnedToViewport extends StatelessWidget {
  final ScrollController controller;
  final double viewport;
  final Widget child;

  const _PinnedToViewport({
    required this.controller,
    required this.viewport,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, pinned) => Transform.translate(
      offset: Offset(controller.hasClients ? controller.offset : 0, 0),
      child: pinned,
    ),
    // A vertical list hands its children a tight width, which a bare SizedBox
    // cannot narrow; Align loosens it and holds the header at the left edge.
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: viewport, child: child),
    ),
  );
}

class _HunkHeaderRow extends StatelessWidget {
  final String header;
  final bool editable;
  final bool staged;
  final VoidCallback onStage;
  final VoidCallback? onDiscard;

  /// Split view draws the marker in the left column and the buttons in the
  /// right one, so each side takes only its half of the header. Inline shows
  /// both.
  final bool showActions;
  final bool showMarker;
  const _HunkHeaderRow({
    required this.header,
    required this.editable,
    required this.staged,
    required this.onStage,
    this.onDiscard,
    this.showActions = true,
    this.showMarker = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: _hunkHeaderHeight,
      color: t.bgApp,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      // Nothing in the hunk header belongs in a copy — neither the @@ marker
      // nor the action buttons, which Select All would otherwise sweep up.
      child: SelectionContainer.disabled(
        child: Row(
          children: [
            Expanded(
              child: showMarker
                  ? Text(
                      header,
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (editable && showActions)
              TextButton(
                onPressed: onStage,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  staged ? 'Unstage hunk' : 'Stage hunk',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (onDiscard != null && showActions)
              TextButton(
                onPressed: onDiscard,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Discard hunk',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Groups hunk lines into left/right pairs for split view: context aligns on
/// both sides; a run of deletions pairs with the following run of additions.
/// Pairs are indices into the hunk's line list rather than the lines
/// themselves, so a half knows which line it is showing — staging a run of
/// selected lines builds its patch from those indices.
List<(int?, int?)> _pairForSplit(List<DiffLine> lines) {
  final out = <(int?, int?)>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].type == DiffLineType.context) {
      out.add((i, i));
      i++;
      continue;
    }
    final dels = <int>[], adds = <int>[];
    while (i < lines.length && lines[i].type == DiffLineType.del) {
      dels.add(i++);
    }
    while (i < lines.length && lines[i].type == DiffLineType.add) {
      adds.add(i++);
    }
    for (var k = 0; k < dels.length || k < adds.length; k++) {
      out.add((
        k < dels.length ? dels[k] : null,
        k < adds.length ? adds[k] : null,
      ));
    }
  }
  return out;
}

/// One column of the split view: its own horizontal scroll and its own width,
/// so an empty or short side cannot crowd out the other. Vertically both
/// columns share [vController], which keeps them on the same row.
///
/// Rows are a fixed [lineHeight] and hunk headers are rendered on both sides —
/// invisibly on the right — because the two lists only stay aligned while
/// their rows agree on height, item for item.
class _SplitColumn extends StatelessWidget {
  final List<_DiffItem> items;
  final bool isLeft;
  final int chars;
  final double charWidth;
  final double lineHeight;
  final ScrollController hController;
  final ScrollController vController;
  final Widget Function(_DiffItem, {bool showActions, bool showMarker}) header;
  final void Function(BuildContext, Offset) onMenu;

  const _SplitColumn({
    required this.items,
    required this.onMenu,
    required this.isLeft,
    required this.chars,
    required this.charWidth,
    required this.lineHeight,
    required this.hController,
    required this.vController,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    final list = LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: hController,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: hController,
          child: SizedBox(
            width: diffContentWidth(
              viewport: constraints.maxWidth,
              chars: chars,
              charWidth: charWidth,
              gutter: kSplitGutterWidth,
            ),
            // Each column is its own selection region, so a copy takes one
            // side's text and never interleaves the two line by line. The
            // region sits inside the scroll view: a viewport between it and
            // its selectables leaves selectAll() with nothing to select.
            child: SelectionArea(
              contextMenuBuilder: (_, _) => const SizedBox.shrink(),
              child: Builder(
                builder: (context) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapUp: (d) => onMenu(context, d.globalPosition),
                  child: ListView.builder(
                    controller: vController,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final it = items[i];
                      if (it.header) {
                        // The marker belongs over the old line numbers on the
                        // left; the buttons act on the hunk as a whole and go
                        // in the right column, where the eye ends up.
                        return _PinnedToViewport(
                          controller: hController,
                          viewport: constraints.maxWidth,
                          child: header(
                            it,
                            showActions: !isLeft,
                            showMarker: isLeft,
                          ),
                        );
                      }
                      final index = isLeft ? it.pair!.$1 : it.pair!.$2;
                      return _SplitHalf(
                        line: index == null
                            ? null
                            : it.file.hunks[it.hunkIndex].lines[index],
                        path: it.file.path,
                        hunkIndex: it.hunkIndex,
                        lineIndex: index,
                        isLeft: isLeft,
                        height: lineHeight,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Only the right column shows a vertical scrollbar; a second one down the
    // middle of the sheet would read as a divider between two documents.
    return isLeft
        ? ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: list,
          )
        : list;
  }
}

class _SplitHalf extends ConsumerWidget {
  final DiffLine? line;
  final String path;
  final int hunkIndex;

  /// Index of the line in the hunk, or null where this half is blank because
  /// only the other side has a line on this row.
  final int? lineIndex;
  final bool isLeft;

  /// Fixed so the two columns' rows line up; code lines never wrap, so every
  /// row is one line tall whatever it holds.
  final double height;

  const _SplitHalf({
    required this.line,
    required this.path,
    required this.hunkIndex,
    required this.lineIndex,
    required this.isLeft,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final index = lineIndex;
    final selected =
        index != null &&
        (ref.watch(lineSelectionProvider)?.covers(path, hunkIndex, index) ??
            false);
    return SizedBox(
      height: height,
      child: LineSelectHandle(
        path: path,
        hunkIndex: hunkIndex,
        lineIndex: index,
        child: _half(t, line, isLeft: isLeft, selected: selected),
      ),
    );
  }

  Widget _half(
    AppTokens t,
    DiffLine? line, {
    required bool isLeft,
    required bool selected,
  }) {
    final lineBg = line == null
        ? Colors.transparent
        : switch (line.type) {
            DiffLineType.add => t.addBg,
            DiffLineType.del => t.delBg,
            DiffLineType.context => Colors.transparent,
          };
    // The picked-out run reads over the add/delete tint rather than replacing
    // it, so a selected line still shows what kind of change it is.
    final bg = selected
        ? Color.alphaBlend(t.accent.withValues(alpha: 0.22), lineBg)
        : lineBg;
    final border = isLeft
        ? Border(right: BorderSide(color: t.border))
        : const Border();
    if (line == null) {
      return DecoratedBox(decoration: BoxDecoration(border: border));
    }
    return Container(
      decoration: BoxDecoration(color: bg, border: border),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: SizedBox(
              width: 34,
              child: Text(
                (isLeft ? line.oldNo : line.newNo)?.toString() ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DiffSelectableLine(
              text: line.text,
              child: Text.rich(
                _lineSpans(t, line),
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends ConsumerWidget {
  final DiffLine line;
  final bool editable;
  final bool staged;
  final VoidCallback? onStage;

  /// Where this line sits, so the gutter can pick it out for staging a run.
  final String path;
  final int hunkIndex;
  final int lineIndex;

  const _LineRow({
    required this.line,
    required this.editable,
    required this.staged,
    required this.onStage,
    required this.path,
    required this.hunkIndex,
    required this.lineIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final selected =
        ref.watch(lineSelectionProvider)?.covers(path, hunkIndex, lineIndex) ??
        false;
    final (lineBg, sign) = switch (line.type) {
      DiffLineType.add => (t.addBg, '+'),
      DiffLineType.del => (t.delBg, '-'),
      DiffLineType.context => (Colors.transparent, ' '),
    };
    // The picked-out run reads over the add/delete tint rather than replacing
    // it, so a selected line still shows what kind of change it is.
    final bg = selected
        ? Color.alphaBlend(t.accent.withValues(alpha: 0.22), lineBg)
        : lineBg;
    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineSelectHandle(
            path: path,
            hunkIndex: hunkIndex,
            lineIndex: lineIndex,
            child: SelectionContainer.disabled(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (editable)
                    SizedBox(
                      width: 20,
                      child: onStage == null
                          ? null
                          : InkWell(
                              onTap: onStage,
                              child: Icon(
                                staged ? Icons.check : Icons.add,
                                size: 12,
                                color: staged ? t.success : t.textFaint,
                              ),
                            ),
                    ),
                  _num(t, line.oldNo),
                  _num(t, line.newNo),
                  const SizedBox(width: 6),
                  Text(
                    sign,
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          Expanded(
            child: DiffSelectableLine(
              text: line.text,
              child: Text.rich(
                _lineSpans(t, line),
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(AppTokens t, int? n) => SizedBox(
    width: 38,
    child: Text(
      n?.toString() ?? '',
      textAlign: TextAlign.right,
      style: TextStyle(
        color: t.textFaint,
        fontSize: 11,
        fontFamily: 'monospace',
      ),
    ),
  );
}

/// Left-aligned monospace spans: word-level highlight for a modified line,
/// else syntax colouring.
TextSpan _lineSpans(AppTokens t, DiffLine line) {
  const base = TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.35);
  if (line.words != null) {
    final wordBg = line.type == DiffLineType.add ? t.addWord : t.delWord;
    return TextSpan(
      children: [
        for (final seg in line.words!)
          TextSpan(
            text: seg.text,
            style: base.copyWith(
              color: t.textPrimary,
              backgroundColor: seg.changed ? wordBg : null,
            ),
          ),
      ],
    );
  }
  return TextSpan(
    children: [
      for (final tok in highlightLine(line.text))
        TextSpan(
          text: tok.text,
          style: base.copyWith(color: syntaxColor(t, tok.kind)),
        ),
    ],
  );
}

/// Segmented Unstaged/Staged control for a partially-staged working-tree file.
class _SideToggle extends StatelessWidget {
  final bool staged;
  final VoidCallback onUnstaged;
  final VoidCallback onStaged;
  const _SideToggle({
    required this.staged,
    required this.onUnstaged,
    required this.onStaged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget seg(String label, bool on, VoidCallback tap) => InkWell(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: on ? t.active : null,
        child: Text(
          label,
          style: TextStyle(
            color: on ? t.textPrimary : t.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg('Unstaged', !staged, onUnstaged),
            seg('Staged', staged, onStaged),
          ],
        ),
      ),
    );
  }
}
