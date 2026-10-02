import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/models.dart';
import '../../domain/git/diff.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_writer.dart';
import '../../domain/git/models.dart';
import '../../domain/git/review.dart';
import '../../domain/text_tabs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/graph_selection.dart';
import '../../state/review.dart';
import '../common/dialogs.dart';
import '../diff/syntax_style.dart';
import '../insight/file_insight_dialog.dart';
import '../insight/line_history_dialog.dart';
import '../workspace/forge_presentation.dart';
import 'review_picker.dart';

final _codeStyle = AppFonts.mns(size: 12, height: 1.35);

/// A branch review in the centre column: base and head, which way the diff is
/// read, the commits head brings, and every changed file's diff in one scroll,
/// each file collapsible and markable as viewed. Read-only throughout — a file
/// opens in the diff sheet for the split view and whole-file reading.
class ReviewView extends ConsumerStatefulWidget {
  const ReviewView({super.key});

  @override
  ConsumerState<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends ConsumerState<ReviewView> {
  /// The reader's own expand/collapse per path. Absent means the default
  /// applies — see [reviewFileExpanded].
  final _choice = <String, bool>{};
  bool _commitsOpen = true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final target = ref.watch(reviewTargetProvider);
    if (target == null) return const SizedBox.shrink();

    // A different pair is a different review; choices made on the old one
    // say nothing about this one.
    ref.listen(reviewTargetProvider, (prev, next) {
      if (prev != next) setState(_choice.clear);
    });

    final summary = ref.watch(reviewSummaryProvider(target));
    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(target: target),
          _ModeBar(target: target, summary: summary.valueOrNull),
          Expanded(
            child: summary.when(
              skipLoadingOnReload: true,
              loading: () => const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => _Message(l.rvCouldNotRead),
              data: (s) => _body(target, s),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ReviewTarget target, ReviewSummary s) {
    final l = AppLocalizations.of(context);
    final from = s.fromRev;
    final diffs = from == null
        ? const AsyncValue<Map<String, FileDiff>>.data({})
        : ref.watch(
            reviewDiffProvider((
              repoPath: target.repoPath,
              from: from,
              to: s.headSha,
            )),
          );
    final marks = ref.watch(reviewViewedProvider(target));
    final byPath = diffs.valueOrNull ?? const <String, FileDiff>{};
    final prints = {
      for (final f in s.files)
        if (byPath[f.path] case final d?) f.path: diffFingerprint(d),
    };
    final viewedCount = [
      for (final e in prints.entries)
        if (isViewed(marks, e.key, e.value)) e.key,
    ].length;
    var adds = 0, dels = 0;
    for (final d in byPath.values) {
      for (final h in d.hunks) {
        for (final line in h.lines) {
          if (line.type == DiffLineType.add) adds++;
          if (line.type == DiffLineType.del) dels++;
        }
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Summary(
            target: target,
            summary: s,
            adds: adds,
            dels: dels,
            viewed: viewedCount,
            onCollapseAll: () => setState(() {
              for (final f in s.files) {
                _choice[f.path] = false;
              }
            }),
            onExpandAll: () => setState(() {
              for (final f in s.files) {
                _choice[f.path] = true;
              }
            }),
          ),
        ),
        if (from == null)
          SliverToBoxAdapter(child: _NoMergeBase(target: target))
        else ...[
          SliverToBoxAdapter(
            child: _Commits(
              summary: s,
              open: _commitsOpen,
              onToggle: () => setState(() => _commitsOpen = !_commitsOpen),
            ),
          ),
          SliverToBoxAdapter(child: _SectionLabel(l.rvFiles)),
          if (s.files.isEmpty)
            SliverToBoxAdapter(child: _Message(l.rvNoChanges))
          else if (diffs.hasError)
            SliverToBoxAdapter(child: _Message(l.rvCouldNotRead))
          else
            for (final f in s.files)
              _FileSliver(
                key: ValueKey(f.path),
                target: target,
                file: f,
                diff: byPath[f.path],
                loading: diffs.isLoading && !diffs.hasValue,
                fromRev: from,
                headRev: s.headSha,
                viewed:
                    prints[f.path] != null &&
                    isViewed(marks, f.path, prints[f.path]!),
                choice: _choice[f.path],
                onToggle: (expanded) =>
                    setState(() => _choice[f.path] = !expanded),
                onViewed: () {
                  final fp = prints[f.path];
                  if (fp == null) return;
                  ref
                      .read(reviewViewedProvider(target).notifier)
                      .toggle(f.path, fp);
                  // Ticking puts the file away; unticking brings it back.
                  // Either way the default now decides, not an older click.
                  setState(() => _choice.remove(f.path));
                },
              ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }
}

/// Title bar: the two sides, swap, change, close.
class _Header extends ConsumerWidget {
  final ReviewTarget target;
  const _Header({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    void set(ReviewTarget? next) =>
        ref.read(reviewTargetProvider.notifier).state = next;

    Widget pill(String label, String tooltip) => Flexible(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () async {
            final next = await showReviewPicker(
              context,
              ref,
              repoPath: target.repoPath,
              initial: target,
            );
            if (next != null) set(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: t.bgElevated,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: t.border),
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            l.rvTitle,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          pill(target.baseLabel, l.rvBase),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_back, size: 13, color: t.textFaint),
          ),
          pill(target.headLabel, l.rvHead),
          const Spacer(),
          IconButton(
            iconSize: 15,
            tooltip: l.rvSwap,
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => set(target.swapped),
          ),
          IconButton(
            iconSize: 15,
            tooltip: l.close,
            icon: const Icon(Icons.close),
            onPressed: () => set(null),
          ),
        ],
      ),
    );
  }
}

/// Which diff is on screen, spelled out, plus the export and pull request
/// actions.
class _ModeBar extends ConsumerWidget {
  final ReviewTarget target;
  final ReviewSummary? summary;
  const _ModeBar({required this.target, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final pr = ref.watch(reviewPullRequestProvider(target)).valueOrNull;
    final caption = target.threeDot
        ? l.rvThreeDotCaption(target.range, target.headLabel, target.baseLabel)
        : l.rvTwoDotCaption(target.range, target.baseLabel, target.headLabel);

    // Each half gives way to the other on a narrow column rather than pushing
    // the toggle past the edge.
    Widget seg(String label, bool on, bool threeDot) => Flexible(
      child: InkWell(
        onTap: on
            ? null
            : () => ref.read(reviewTargetProvider.notifier).state = target
                  .withThreeDot(threeDot),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: on ? t.active : null,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? t.textPrimary : t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    seg(l.rvModeThreeDot, target.threeDot, true),
                    seg(l.rvModeTwoDot, !target.threeDot, false),
                  ],
                ),
              ),
              _ExportButton(target: target, summary: summary),
              if (pr != null) _PrButton(pr: pr.pr, host: pr.host),
            ],
          ),
          const SizedBox(height: 6),
          Text(caption, style: TextStyle(color: t.textMuted, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _ExportButton extends ConsumerWidget {
  final ReviewTarget target;
  final ReviewSummary? summary;
  const _ExportButton({required this.target, required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = summary;
    // Patches are head's commits over base; with none there is nothing to
    // write.
    final enabled = s != null && s.counts.ahead > 0;
    return PopupMenuButton<void>(
      enabled: enabled,
      tooltip: l.rvExport,
      itemBuilder: (_) => [
        PopupMenuItem(
          height: 34,
          onTap: () => _save(context, ref, s!),
          child: Text(l.rvSavePatches, style: const TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          height: 34,
          onTap: () => _copy(ref, l, s!),
          child: Text(l.rvCopyPatch, style: const TextStyle(fontSize: 13)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ios_share,
              size: 13,
              color: enabled ? t.textMuted : t.textFaint,
            ),
            const SizedBox(width: 4),
            Text(
              l.rvExport,
              style: TextStyle(
                color: enabled ? t.textMuted : t.textFaint,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  GitWriter _writer(WidgetRef ref) =>
      GitWriter(ref.read(gitServiceProvider), target.repoPath);

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    ReviewSummary s,
  ) async {
    final l = AppLocalizations.of(context);
    final toast = ref.read(toastProvider.notifier);
    final dir = await getDirectoryPath();
    if (dir == null) return;
    try {
      final files = await _writer(ref)
          .formatPatchToDir(s.baseSha, s.headSha, dir);
      toast.show(l.rvPatchesSaved(files.length, dir), kind: ToastKind.success);
    } catch (e) {
      toast.show(l.rvExportFailed, description: '$e', kind: ToastKind.error);
    }
  }

  Future<void> _copy(WidgetRef ref, AppLocalizations l, ReviewSummary s) async {
    final toast = ref.read(toastProvider.notifier);
    try {
      final text = await _writer(ref).formatPatch(s.baseSha, s.headSha);
      await Clipboard.setData(ClipboardData(text: text));
      toast.show(l.rvPatchCopied, kind: ToastKind.success);
    } catch (e) {
      toast.show(l.rvExportFailed, description: '$e', kind: ToastKind.error);
    }
  }
}

class _PrButton extends ConsumerWidget {
  final PullRequest pr;
  final ForgeHost host;
  const _PrButton({required this.pr, required this.host});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final gitlab = host.kind == ForgeKind.gitlab;
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () async {
        // Built from the locally resolved host and a plain number, never from
        // a URL the forge sent back.
        final opened = await ref.read(forgeLaunchUrlProvider)(
          pullRequestWebUrl(host, pr.number),
        );
        if (!opened) {
          ref
              .read(toastProvider.notifier)
              .show(
                gitlab ? l.forgeCouldNotOpenMr : l.forgeCouldNotOpenPr,
                kind: ToastKind.error,
              );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 13, color: t.accent),
            const SizedBox(width: 4),
            Text(
              gitlab ? l.rvOpenMr(pr.number) : l.rvOpenPr(pr.number),
              style: TextStyle(color: t.accent, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ahead/behind, size of the change, and progress through it.
class _Summary extends StatelessWidget {
  final ReviewTarget target;
  final ReviewSummary summary;
  final int adds;
  final int dels;
  final int viewed;
  final VoidCallback onCollapseAll;
  final VoidCallback onExpandAll;
  const _Summary({
    required this.target,
    required this.summary,
    required this.adds,
    required this.dels,
    required this.viewed,
    required this.onCollapseAll,
    required this.onExpandAll,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final muted = TextStyle(color: t.textMuted, fontSize: 12);
    Widget link(String label, VoidCallback onTap) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(label, style: TextStyle(color: t.accent, fontSize: 12)),
      ),
    );
    final files = summary.files.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l.rvAheadBehind(
              target.headLabel,
              summary.counts.ahead,
              summary.counts.behind,
              target.baseLabel,
            ),
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (summary.fromRev != null) ...[
            Text(l.rvFileCount(files), style: muted),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '+$adds',
                    style: TextStyle(color: t.success),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: '−$dels',
                    style: TextStyle(color: t.danger),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12),
            ),
            if (files > 0) ...[
              Text(l.rvViewedCount(viewed, files), style: muted),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  link(l.rvCollapseAll, onCollapseAll),
                  link(l.rvExpandAll, onExpandAll),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NoMergeBase extends ConsumerWidget {
  final ReviewTarget target;
  const _NoMergeBase({required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.rvNoMergeBase(target.baseLabel, target.headLabel),
            style: TextStyle(color: t.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => ref.read(reviewTargetProvider.notifier).state =
                target.withThreeDot(false),
            child: Text(l.rvUseTwoDot),
          ),
        ],
      ),
    );
  }
}

class _Commits extends ConsumerWidget {
  final ReviewSummary summary;
  final bool open;
  final VoidCallback onToggle;
  const _Commits({
    required this.summary,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final commits = summary.commits;
    final selected = ref.watch(selectedCommitProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 4),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: t.textFaint,
                ),
                const SizedBox(width: 2),
                Text(
                  l.rvCommits(commits.length),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          if (commits.isEmpty) _Message(l.rvNoCommits),
          for (final c in commits)
            InkWell(
              onTap: () =>
                  ref.read(selectedCommitProvider.notifier).state = c.sha,
              child: Container(
                color: selected == c.sha ? t.active : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    Text(
                      c.sha.substring(0, 7),
                      style: _codeStyle.copyWith(
                        color: t.textFaint,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.message,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 0,
                      child: Text(
                        c.author,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (summary.commitsTruncated)
            _Message(l.rvCommitsTruncated(commits.length)),
        ],
      ],
    );
  }
}

/// One file of the review: its header, and when expanded its diff lines,
/// built lazily so a long file costs only what is on screen.
class _FileSliver extends ConsumerWidget {
  final ReviewTarget target;
  final CommitFileChange file;
  final FileDiff? diff;
  final bool loading;
  final String fromRev;
  final String headRev;
  final bool viewed;
  final bool? choice;
  final void Function(bool expanded) onToggle;
  final VoidCallback onViewed;

  const _FileSliver({
    super.key,
    required this.target,
    required this.file,
    required this.diff,
    required this.loading,
    required this.fromRev,
    required this.headRev,
    required this.viewed,
    required this.choice,
    required this.onToggle,
    required this.onViewed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = diff;
    final rows = <_Row>[
      if (d != null)
        for (final h in d.hunks) ...[
          _Row.header(h.header),
          for (final line in h.lines) _Row.line(line),
        ],
    ];
    final lineCount = rows.length;
    final expanded = reviewFileExpanded(
      choice: choice,
      viewed: viewed,
      lineCount: lineCount,
    );
    final showNote =
        expanded &&
        d != null &&
        rows.isEmpty; // binary, LFS, or a pure rename / mode change
    final large = !expanded && choice == null && !viewed && lineCount > 0;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _FileHeader(
            target: target,
            file: file,
            diff: d,
            fromRev: fromRev,
            headRev: headRev,
            expanded: expanded,
            viewed: viewed,
            onToggle: () => onToggle(expanded),
            onViewed: d == null ? null : onViewed,
          ),
        ),
        if (expanded && loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (showNote)
          SliverToBoxAdapter(
            child: _Message(
              d.binary || d.lfs != null
                  ? AppLocalizations.of(context).rvBinary
                  : AppLocalizations.of(context).rvNoContentChange,
            ),
          ),
        if (large)
          SliverToBoxAdapter(
            child: _Message(
              AppLocalizations.of(context).rvLargeDiff(lineCount),
            ),
          ),
        if (expanded && rows.isNotEmpty)
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              return row.line == null
                  ? _HunkHeader(row.header!)
                  : _LineView(
                      line: row.line!,
                      onMenu: (at) => _lineMenu(context, at, row.line!),
                    );
            },
          ),
      ],
    );
  }

  void _lineMenu(BuildContext context, Offset at, DiffLine line) {
    final anchor = lineHistoryAnchor(
      line,
      path: file.path,
      oldPath: file.origPath,
      headRev: headRev,
      fromRev: fromRev,
    );
    if (anchor == null) return;
    final l = AppLocalizations.of(context);
    showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () => showLineHistory(
            context,
            repoPath: target.repoPath,
            path: anchor.path,
            start: anchor.line,
            end: anchor.line,
            rev: anchor.rev,
          ),
          child: Text(l.lhLineHistory, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _Row {
  final String? header;
  final DiffLine? line;
  const _Row.header(String this.header) : line = null;
  const _Row.line(DiffLine this.line) : header = null;
}

class _FileHeader extends ConsumerWidget {
  final ReviewTarget target;
  final CommitFileChange file;
  final FileDiff? diff;
  final String fromRev;
  final String headRev;
  final bool expanded;
  final bool viewed;
  final VoidCallback onToggle;
  final VoidCallback? onViewed;

  const _FileHeader({
    required this.target,
    required this.file,
    required this.diff,
    required this.fromRev,
    required this.headRev,
    required this.expanded,
    required this.viewed,
    required this.onToggle,
    required this.onViewed,
  });

  DiffTarget get _diffTarget => DiffTarget(
    repoPath: target.repoPath,
    path: file.path,
    baseRev: fromRev,
    commitSha: headRev,
    origPath: file.origPath,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final (color, letter) = switch (file.change) {
      GitChange.added => (t.success, 'A'),
      GitChange.deleted => (t.danger, 'D'),
      GitChange.renamed => (t.accent, 'R'),
      GitChange.copied => (t.accent, 'C'),
      _ => (t.warning, 'M'),
    };
    var adds = 0, dels = 0;
    for (final h in diff?.hunks ?? const <DiffHunk>[]) {
      for (final line in h.lines) {
        if (line.type == DiffLineType.add) adds++;
        if (line.type == DiffLineType.del) dels++;
      }
    }
    final label = file.origPath == null
        ? file.path
        : '${file.origPath} → ${file.path}';
    // Deleted on head, so there is nothing at head to blame or walk back from.
    final atHead = file.change != GitChange.deleted;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.symmetric(horizontal: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.only(left: 6, right: 4),
      height: 32,
      child: Row(
        children: [
          InkWell(
            key: ValueKey('rv-toggle-${file.path}'),
            onTap: onToggle,
            child: Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: t.textFaint,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            letter,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onToggle,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: _codeStyle.copyWith(
                  color: viewed ? t.textFaint : t.textPrimary,
                ),
              ),
            ),
          ),
          if (adds > 0 || dels > 0) ...[
            const SizedBox(width: 8),
            Text('+$adds', style: TextStyle(color: t.success, fontSize: 11)),
            const SizedBox(width: 4),
            Text('−$dels', style: TextStyle(color: t.danger, fontSize: 11)),
          ],
          const SizedBox(width: 8),
          InkWell(
            key: ValueKey('rv-viewed-${file.path}'),
            onTap: onViewed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    viewed ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 15,
                    color: viewed ? t.accent : t.textFaint,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    l.rvViewed,
                    style: TextStyle(color: t.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<void>(
            iconSize: 15,
            icon: Icon(Icons.more_horiz, color: t.textFaint),
            padding: EdgeInsets.zero,
            itemBuilder: (_) => [
              PopupMenuItem(
                height: 34,
                onTap: () =>
                    ref.read(diffTargetProvider.notifier).state = _diffTarget,
                child: Text(
                  l.rvOpenInDiff,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (atHead) ...[
                PopupMenuItem(
                  height: 34,
                  onTap: () => showFileInsight(
                    context,
                    repoPath: target.repoPath,
                    path: file.path,
                    rev: headRev,
                  ),
                  child: Text(
                    l.rvFileHistoryAtHead,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                PopupMenuItem(
                  height: 34,
                  onTap: () => showFileInsight(
                    context,
                    repoPath: target.repoPath,
                    path: file.path,
                    initialTab: 1,
                    rev: headRev,
                  ),
                  child: Text(
                    l.rvBlameAtHead,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HunkHeader extends StatelessWidget {
  final String header;
  const _HunkHeader(this.header);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        header,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: _codeStyle.copyWith(color: t.textFaint, fontSize: 11),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  final DiffLine line;
  final void Function(Offset at) onMenu;
  const _LineView({required this.line, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (bg, sign) = switch (line.type) {
      DiffLineType.add => (t.addBg, '+'),
      DiffLineType.del => (t.delBg, '-'),
      DiffLineType.context => (Colors.transparent, ' '),
    };
    Widget num(int? n) => SizedBox(
      width: 40,
      child: Text(
        n?.toString() ?? '',
        textAlign: TextAlign.right,
        style: _codeStyle.copyWith(color: t.textFaint, fontSize: 11),
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: Container(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            num(line.oldNo),
            num(line.newNo),
            const SizedBox(width: 6),
            Text(sign, style: _codeStyle.copyWith(color: t.textFaint)),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                _spans(t, line.text),
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _spans(AppTokens t, String text) {
    // Tabs advance to the next stop from wherever they sit, so the column has
    // to carry across token boundaries.
    var column = 0;
    return TextSpan(
      children: [
        for (final tok in highlightLine(text))
          TextSpan(
            text: () {
              final r = expandTabsFrom(tok.text, column);
              column = r.column;
              return r.text;
            }(),
            style: _codeStyle.copyWith(color: syntaxColor(t, tok.kind)),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      child: Text(
        text,
        style: TextStyle(
          color: t.textFaint,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Text(text, style: TextStyle(color: t.textMuted, fontSize: 12)),
    );
  }
}
