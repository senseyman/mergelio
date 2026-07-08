import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../domain/git/rebase_plan.dart';
import '../../domain/search.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/search.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../common/dialogs.dart';
import '../rebase/rebase_editor.dart';
import 'commit_columns.dart';
import 'commit_row.dart';
import 'rail_metrics.dart';
import 'squash_overlay.dart';

/// Centre panel: the commit graph for the active repo. Loads [RepoData] and
/// hands it to [GraphList]; shows nothing when no repo tab is active.
class GraphView extends ConsumerWidget {
  const GraphView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final path = ref.watch(workspaceProvider).activeTab?.path;
    if (path == null) return Container(color: t.bgApp);

    return Container(
      color: t.bgApp,
      child: ref
          .watch(repoDataProvider(path))
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
                'Could not read repository',
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            data: (d) => GraphList(data: d),
          ),
    );
  }
}

/// The graph itself: header with the Columns menu, then a virtualised list of
/// fixed-height rows — a WIP row on top when the working tree is dirty,
/// followed by the commits. Arrow keys move the selection and keep it visible.
class GraphList extends ConsumerStatefulWidget {
  final RepoData data;
  const GraphList({super.key, required this.data});

  @override
  ConsumerState<GraphList> createState() => _GraphListState();
}

class _GraphListState extends ConsumerState<GraphList> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'graph');

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasWip => widget.data.working.isNotEmpty;

  /// Selection order: WIP row first (when present), then commits top-down.
  List<String> get _order => [
    if (_hasWip) wipSelection,
    for (final c in widget.data.commits) c.sha,
  ];

  void _select(String id, double rowHeight) {
    ref.read(selectedCommitProvider.notifier).state = id;
    final i = _order.indexOf(id);
    if (i < 0 || !_scroll.hasClients) return;
    final top = i * rowHeight;
    final viewTop = _scroll.offset;
    final viewBottom = viewTop + _scroll.position.viewportDimension;
    if (top < viewTop) {
      _scroll.animateTo(
        top,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (top + rowHeight > viewBottom) {
      _scroll.animateTo(
        top + rowHeight - _scroll.position.viewportDimension,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  /// Selects and flies to the next/previous search match relative to the
  /// current selection.
  void _jumpMatch(
    RepoData d,
    Set<String> matches,
    bool forward,
    RailMetrics metrics,
  ) {
    if (matches.isEmpty) return;
    final ordered = [
      for (final c in d.commits)
        if (matches.contains(c.sha)) c.sha,
    ];
    final current = ref.read(selectedCommitProvider);
    final at = current == null ? -1 : ordered.indexOf(current);
    final next = forward
        ? (at + 1) % ordered.length
        : (at - 1 + ordered.length) % ordered.length;
    _select(ordered[next], metrics.rowHeight);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, double rowHeight) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final order = _order;
    if (order.isEmpty) return KeyEventResult.ignored;
    final current = ref.read(selectedCommitProvider);
    final i = current == null ? -1 : order.indexOf(current);
    final next = (i + delta).clamp(0, order.length - 1);
    _select(order[next], rowHeight);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final compact = ref.watch(settingsProvider.select((s) => s.graphCompact));
    final cols = ref.watch(settingsProvider.select((s) => s.graphCols));
    final selected = ref.watch(selectedCommitProvider);
    final metrics = RailMetrics(compact: compact);

    var maxLane = 0;
    for (final c in d.commits) {
      if (c.lane > maxLane) maxLane = c.lane;
      for (final l in c.through) {
        if (l > maxLane) maxLane = l;
      }
    }
    final labels = deriveBranchLabels(d.commits);

    final wipRows = _hasWip ? 1 : 0;

    final rowIndex = <String, int>{};
    final laneOf = <String, ({int lane, int ci})>{};
    for (var j = 0; j < d.commits.length; j++) {
      final c = d.commits[j];
      rowIndex[c.sha] = j;
      laneOf[c.sha] = (lane: c.lane, ci: c.ci);
    }
    final segments = resolveSquashSegments(
      d.squashLinks,
      rowIndex,
      laneOf: laneOf,
    );

    final query = ref.watch(searchQueryProvider);
    final matchShas = query == null || query.isEmpty
        ? const <String>{}
        : {
            for (final c in d.commits)
              if (matchesCommit(c, query)) c.sha,
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (query != null)
          _SearchBar(
            query: query,
            matchCount: matchShas.length,
            onChanged: (q) => ref.read(searchQueryProvider.notifier).state = q,
            onClose: () => ref.read(searchQueryProvider.notifier).state = null,
            onJump: (forward) => _jumpMatch(d, matchShas, forward, metrics),
          )
        else
          _GraphHeader(cols: cols, compact: compact),
        Expanded(
          child: Focus(
            focusNode: _focus,
            onKeyEvent: (n, e) => _onKey(n, e, metrics.rowHeight),
            child: GestureDetector(
              onTap: _focus.requestFocus,
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    itemExtent: metrics.rowHeight,
                    itemCount: d.commits.length + wipRows,
                    itemBuilder: (context, i) {
                      if (_hasWip && i == 0) {
                        return _WipRow(
                          metrics: metrics,
                          maxLane: maxLane,
                          fileCount: d.working.length,
                          selected: selected == wipSelection,
                          onTap: () {
                            _focus.requestFocus();
                            _select(wipSelection, metrics.rowHeight);
                          },
                        );
                      }
                      final c = d.commits[i - wipRows];
                      return _CommitContextMenu(
                        commit: c,
                        child: CommitRow(
                          commit: c,
                          branchLabel: labels[c.sha],
                          metrics: metrics,
                          maxLane: maxLane,
                          cols: cols,
                          selected: selected == c.sha,
                          searchMatch: query == null || query.isEmpty
                              ? null
                              : matchShas.contains(c.sha),
                          onTap: () {
                            _focus.requestFocus();
                            _select(c.sha, metrics.rowHeight);
                          },
                        ),
                      );
                    },
                  ),
                  if (segments.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _scroll,
                          builder: (context, _) => CustomPaint(
                            painter: SquashOverlayPainter(
                              segments: segments,
                              metrics: metrics,
                              scrollOffset: _scroll.hasClients
                                  ? _scroll.offset
                                  : 0,
                              headerRows: wipRows,
                              palette: context.tokens.branchPalette,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Global-search bar shown in place of the header while a search is open.
class _SearchBar extends StatelessWidget {
  final CommitQuery query;
  final int matchCount;
  final ValueChanged<CommitQuery> onChanged;
  final VoidCallback onClose;
  final void Function(bool forward) onJump;
  const _SearchBar({
    required this.query,
    required this.matchCount,
    required this.onChanged,
    required this.onClose,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 15, color: t.textFaint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              autofocus: true,
              onChanged: (v) => onChanged(
                CommitQuery(
                  text: v,
                  author: query.author,
                  hideMerges: query.hideMerges,
                  hideTags: query.hideTags,
                ),
              ),
              onSubmitted: (_) => onJump(true),
              style: TextStyle(color: t.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search commits…',
                hintStyle: TextStyle(color: t.textFaint, fontSize: 13),
              ),
            ),
          ),
          _FilterChip(
            label: 'Hide merges',
            on: query.hideMerges,
            onTap: () => onChanged(
              CommitQuery(
                text: query.text,
                author: query.author,
                hideMerges: !query.hideMerges,
                hideTags: query.hideTags,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Hide tags',
            on: query.hideTags,
            onTap: () => onChanged(
              CommitQuery(
                text: query.text,
                author: query.author,
                hideMerges: query.hideMerges,
                hideTags: !query.hideTags,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$matchCount',
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
          IconButton(
            iconSize: 16,
            tooltip: 'Previous (⇧N)',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => onJump(false),
          ),
          IconButton(
            iconSize: 16,
            tooltip: 'Next (N)',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => onJump(true),
          ),
          IconButton(
            iconSize: 16,
            tooltip: 'Close (Esc)',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? t.accent.withValues(alpha: 0.16) : null,
          border: Border.all(color: on ? Colors.transparent : t.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? t.accent : t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GraphHeader extends ConsumerWidget {
  final Map<String, bool> cols;
  final bool compact;
  const _GraphHeader({required this.cols, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ctl = ref.read(settingsProvider.notifier);
    const names = {
      'branch': 'Branch',
      'author': 'Author',
      'date': 'Date',
      'sha': 'SHA',
    };
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            'HISTORY',
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Columns',
            onSelected: (id) => id == 'compact'
                ? ctl.toggleGraphCompact()
                : ctl.toggleGraphCol(id),
            itemBuilder: (context) => [
              for (final e in names.entries)
                CheckedPopupMenuItem(
                  value: e.key,
                  checked: cols[e.key] ?? true,
                  height: 36,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)),
                ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'compact',
                checked: compact,
                height: 36,
                child: const Text('Compact', style: TextStyle(fontSize: 13)),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Columns',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  Icon(Icons.arrow_drop_down, size: 16, color: t.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uncommitted-changes row pinned above the newest commit: dashed amber node
/// and a summary of how many files changed. Disappears when the tree is clean.
class _WipRow extends StatelessWidget {
  final RailMetrics metrics;
  final int maxLane;
  final int fileCount;
  final bool selected;
  final VoidCallback onTap;

  const _WipRow({
    required this.metrics,
    required this.maxLane,
    required this.fileCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      hoverColor: t.hover,
      child: Container(
        height: metrics.rowHeight,
        color: selected ? t.active : null,
        child: Row(
          children: [
            SizedBox(
              width: metrics.railWidth(maxLane),
              child: CustomPaint(
                size: Size(metrics.railWidth(maxLane), metrics.rowHeight),
                painter: _WipRailPainter(m: metrics, color: t.warning),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'WIP',
                    style: TextStyle(
                      color: t.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Uncommitted changes · '
                      '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed ring at lane 0 with a strand continuing down to the commit below.
class _WipRailPainter extends CustomPainter {
  final RailMetrics m;
  final Color color;
  const _WipRailPainter({required this.m, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final x = m.laneX(0);
    final y = m.nodeY;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;

    canvas.drawLine(Offset(x, y), Offset(x, size.height), stroke);

    const dash = 4.0, gap = 3.0;
    final ring = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, y), radius: 7));
    for (final metric in ring.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), stroke);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_WipRailPainter old) =>
      old.color != color || old.m.compact != m.compact;
}

/// Right-click scaffold; every mutation lands in a later stage, Copy SHA works
/// now.
/// Per-commit right-click menu wired to real, undoable git operations.
class _CommitContextMenu extends ConsumerWidget {
  final Commit commit;
  final Widget child;
  const _CommitContextMenu({required this.commit, required this.child});

  Future<void> _open(BuildContext context, WidgetRef ref, Offset at) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    final sha = commit.sha;

    PopupMenuItem<void> item(
      String label,
      VoidCallback onTap, {
      bool danger = false,
    }) => PopupMenuItem(
      height: 34,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: danger ? context.tokens.danger : null,
        ),
      ),
    );

    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        item('Create branch here', () async {
          final name = await showInputDialog(
            context,
            title: 'Create branch',
            label: 'Branch name',
          );
          if (name != null) await actions.createBranch(name, at: sha);
        }),
        item('Create tag here', () async {
          final name = await showInputDialog(
            context,
            title: 'Create tag',
            label: 'Tag name',
          );
          if (name != null) await actions.createTag(name, at: sha);
        }),
        item('Cherry-pick', () => actions.cherryPick(sha)),
        item('Revert', () => actions.revert(sha)),
        item('Rebase to here…', () async {
          final steps = await actions.rebaseStepsFrom(sha);
          if (steps.isEmpty) return;
          if (!context.mounted) return;
          final plan = await showRebaseEditor(context, steps: steps);
          if (plan == null || isNoOpPlan(steps, plan)) return; // unchanged
          await actions.rebase(sha, plan);
        }),
        item('Reset here (--hard)', () async {
          final ok = await showConfirmDialog(
            context,
            title: 'Reset to ${commit.shortSha}?',
            body:
                'Moves the current branch to this commit and discards all '
                'uncommitted changes. This cannot be undone from disk.',
            confirmLabel: 'Reset --hard',
          );
          if (ok) await actions.resetHard(sha);
        }, danger: true),
        const PopupMenuDivider(),
        item('Copy SHA', () => Clipboard.setData(ClipboardData(text: sha))),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onSecondaryTapUp: (d) => _open(context, ref, d.globalPosition),
    child: child,
  );
}
