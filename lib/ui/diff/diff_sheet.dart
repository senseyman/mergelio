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
import 'syntax_style.dart';

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
      // Closing the sheet mid-edit would drop the typed text without a word.
      if (editing && ref.read(diffEditorDirtyProvider)) {
        final ok = await confirmDestructive(
          ref,
          context,
          title: 'Discard edits?',
          body:
              'What you typed in ${target.path} has not been written to the '
              'working tree.',
          confirmLabel: 'Discard',
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
              child: const Text('Edit'),
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
            tooltip: 'Close',
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
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final t = context.tokens;
    final split = ref.watch(settingsProvider.select((s) => s.diffSplit));
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

            Future<void> discard(FileDiff file, int hunkIndex) async {
              final patch = buildStagePatch(file, hunkIndex);
              if (patch == null) return;
              final ok = await confirmDestructive(
                ref,
                context,
                title: 'Discard hunk?',
                body:
                    'This removes the selected changes from the working tree. '
                    'You can undo it.',
                confirmLabel: 'Discard',
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
            return LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                controller: _hScroll,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hScroll,
                  child: SizedBox(
                    width: diffContentWidth(
                      viewport: constraints.maxWidth,
                      chars: longestLineChars(doc.files),
                      charWidth: _codeCharWidth(context),
                      split: split,
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
                              showDiffSelectionMenu(context, d.globalPosition),
                          child: ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final it = items[i];
                              final hunk = it.file.hunks[it.hunkIndex];
                              if (it.header) {
                                // The whole-file view collapses everything into one
                                // hunk, so a "stage hunk" there would silently act on
                                // the entire file. Line-level staging still applies.
                                return _HunkHeaderRow(
                                  header: hunk.header,
                                  editable: doc.editable && !target.wholeFile,
                                  staged: doc.staged,
                                  onStage: () =>
                                      apply(it.file, it.hunkIndex, null),
                                  onDiscard: doc.staged || target.wholeFile
                                      ? null
                                      : () => discard(it.file, it.hunkIndex),
                                );
                              }
                              if (it.pair != null) {
                                return _SplitRow(
                                  left: it.pair!.$1,
                                  right: it.pair!.$2,
                                );
                              }
                              final li = it.lineIndex!;
                              final line = hunk.lines[li];
                              return _LineRow(
                                line: line,
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
            );
          },
        );
  }
}

/// Width of one character in the code font, so the widest line can be sized
/// without laying every line out. The font is monospace, so any glyph will do.
double _codeCharWidth(BuildContext context) {
  final painter = TextPainter(
    text: const TextSpan(
      text: 'M',
      style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.35),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

/// One virtualised row of the diff body: a hunk header, an inline line, or a
/// split pair.
class _DiffItem {
  final FileDiff file;
  final int hunkIndex;
  final bool header;
  final int? lineIndex;
  final (DiffLine?, DiffLine?)? pair;
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

class _HunkHeaderRow extends StatelessWidget {
  final String header;
  final bool editable;
  final bool staged;
  final VoidCallback onStage;
  final VoidCallback? onDiscard;
  const _HunkHeaderRow({
    required this.header,
    required this.editable,
    required this.staged,
    required this.onStage,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.bgApp,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      // Nothing in the hunk header belongs in a copy — neither the @@ marker
      // nor the action buttons, which Select All would otherwise sweep up.
      child: SelectionContainer.disabled(
        child: Row(
          children: [
            Expanded(
              child: Text(
                header,
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (editable)
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
            if (onDiscard != null)
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
List<(DiffLine?, DiffLine?)> _pairForSplit(List<DiffLine> lines) {
  final out = <(DiffLine?, DiffLine?)>[];
  var i = 0;
  while (i < lines.length) {
    final l = lines[i];
    if (l.type == DiffLineType.context) {
      out.add((l, l));
      i++;
      continue;
    }
    final dels = <DiffLine>[], adds = <DiffLine>[];
    while (i < lines.length && lines[i].type == DiffLineType.del) {
      dels.add(lines[i++]);
    }
    while (i < lines.length && lines[i].type == DiffLineType.add) {
      adds.add(lines[i++]);
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

class _SplitRow extends StatelessWidget {
  final DiffLine? left;
  final DiffLine? right;
  const _SplitRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: SplitSelectionSide(
            isLeft: true,
            child: _half(t, left, isLeft: true),
          ),
        ),
        Expanded(
          child: SplitSelectionSide(
            isLeft: false,
            child: _half(t, right, isLeft: false),
          ),
        ),
      ],
    );
  }

  Widget _half(AppTokens t, DiffLine? line, {required bool isLeft}) {
    final bg = line == null
        ? Colors.transparent
        : switch (line.type) {
            DiffLineType.add => t.addBg,
            DiffLineType.del => t.delBg,
            DiffLineType.context => Colors.transparent,
          };
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

class _LineRow extends StatelessWidget {
  final DiffLine line;
  final bool editable;
  final bool staged;
  final VoidCallback? onStage;
  const _LineRow({
    required this.line,
    required this.editable,
    required this.staged,
    required this.onStage,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (bg, sign) = switch (line.type) {
      DiffLineType.add => (t.addBg, '+'),
      DiffLineType.del => (t.delBg, '-'),
      DiffLineType.context => (Colors.transparent, ' '),
    };
    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
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
