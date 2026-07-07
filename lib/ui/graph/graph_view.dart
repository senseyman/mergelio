import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
class _CommitContextMenu extends StatelessWidget {
  final Commit commit;
  final Widget child;
  const _CommitContextMenu({required this.commit, required this.child});

  void _open(BuildContext context, Offset at) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        _item('Create branch here'),
        _item('Create tag here'),
        _item('Cherry-pick'),
        _item('Revert'),
        _item('Reset here'),
        const PopupMenuDivider(),
        PopupMenuItem(
          height: 34,
          onTap: () => Clipboard.setData(ClipboardData(text: commit.sha)),
          child: const Text('Copy SHA', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  PopupMenuItem<void> _item(String label) => PopupMenuItem(
    height: 34,
    enabled: false,
    child: Text(label, style: const TextStyle(fontSize: 13)),
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapUp: (d) => _open(context, d.globalPosition),
    child: child,
  );
}
