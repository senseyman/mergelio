import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'commit_columns.dart';
import 'graph_rail.dart';
import 'rail_metrics.dart';
import 'ref_pill.dart';

/// One graph row: an optional branch-name gutter, the painted rail cell, then
/// avatar · message · signed badge · tag pills, with a meta line
/// (author/date/sha, each toggleable) in the two-line layout. Compact mode
/// collapses to a single line.
class CommitRow extends StatelessWidget {
  final Commit commit;
  final List<String> branchLabels;

  /// True only on the top row of a contiguous branch segment, so the gutter
  /// prints the branch name once instead of repeating it down the column.
  final bool showBranchLabel;
  final RailMetrics metrics;
  final int maxLane;
  final Map<String, bool> cols;
  final bool selected;
  final String dateFormat;

  /// Search state: a matched row highlights, a non-match dims. Both null when
  /// no search is active.
  final bool? searchMatch;
  final VoidCallback onTap;

  const CommitRow({
    super.key,
    required this.commit,
    required this.branchLabels,
    this.showBranchLabel = false,
    required this.metrics,
    required this.maxLane,
    required this.cols,
    required this.selected,
    this.dateFormat = 'medium',
    this.searchMatch,
    required this.onTap,
  });

  bool _on(String id) => cols[id] ?? true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = commit;
    final compact = metrics.compact;
    final dim = searchMatch == false;
    final highlight = searchMatch == true;
    final nl = c.message.indexOf('\n');
    final firstLine = nl < 0 ? c.message : c.message.substring(0, nl);

    return Semantics(
      button: true,
      selected: selected,
      label: AppLocalizations.of(
        context,
      ).a11yCommitRow(c.shortSha, c.author, firstLine),
      child: InkWell(
        onTap: onTap,
        hoverColor: t.hover,
        child: Opacity(
          opacity: dim ? 0.35 : 1,
          child: Container(
            height: metrics.rowHeight,
            // Selection always wins so the flown-to match is distinguishable;
            // other matches get a lighter tint.
            color: selected
                ? t.active
                : (highlight ? t.accent.withValues(alpha: 0.12) : null),
            child: Row(
              children: [
                if (_on('branch')) _branchColumn(t, c),
                // Clip so a graph wider than the (user-set) rail width is
                // hidden rather than bleeding into the commit details.
                ClipRect(
                  child: SizedBox(
                    width: metrics.railWidth(maxLane),
                    child: CustomPaint(
                      size: Size(metrics.railWidth(maxLane), metrics.rowHeight),
                      painter: GraphRailPainter(
                        c: c,
                        m: metrics,
                        palette: t.branchPalette,
                        nodeFill: t.bgApp,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _Avatar(commit: c, size: compact ? 18 : 24),
                const SizedBox(width: 10),
                Expanded(child: compact ? _singleLine(t, c) : _twoLines(t, c)),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _twoLines(AppTokens t, Commit c) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_titleLine(t, c), const SizedBox(height: 3), _metaLine(t, c)],
  );

  Widget _singleLine(AppTokens t, Commit c) => Row(
    children: [
      Flexible(child: _titleLine(t, c)),
      const SizedBox(width: 10),
      _metaLine(t, c),
    ],
  );

  /// Left gutter that names each branch once, at the top of its segment. Right-
  /// aligned so the name sits flush against the rail, tinted with the lane's
  /// colour and capped with a matching dot.
  Widget _branchColumn(AppTokens t, Commit c) {
    if (!showBranchLabel || branchLabels.isEmpty) {
      return SizedBox(width: metrics.branchWidth);
    }
    final color = t.branchColor(c.ci);
    // Stack all branches on this commit, capped by how many chips fit the row;
    // the rest collapse into a '+N' chip (its tooltip lists them).
    final maxChips = (metrics.rowHeight ~/ 16).clamp(1, 5);
    final List<String> shown;
    final int overflow;
    if (branchLabels.length <= maxChips) {
      shown = branchLabels;
      overflow = 0;
    } else {
      shown = branchLabels.sublist(0, maxChips - 1);
      overflow = branchLabels.length - shown.length;
    }
    return SizedBox(
      width: metrics.branchWidth,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final name in shown) _branchChip(name, color),
            if (overflow > 0)
              Tooltip(
                message: branchLabels.skip(maxChips - 1).join('\n'),
                child: _branchChip('+$overflow', t.textFaint, dot: false),
              ),
          ],
        ),
      ),
    );
  }

  /// One right-aligned branch chip: ellipsized name flush to the rail, capped
  /// with a matching dot (omitted for the '+N' overflow chip).
  Widget _branchChip(String name, Color color, {bool dot = true}) => Row(
    mainAxisSize: MainAxisSize.max,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Flexible(
        child: Text(
          name,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (dot)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
    ],
  );

  Widget _titleLine(AppTokens t, Commit c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          c.message,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (c.signed)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.verified_user_outlined, size: 12, color: t.success),
        ),
      // Branch heads live in the left column now; only HEAD and tags stay inline
      // since they mark a specific commit, not a whole strand.
      for (final r in c.refs)
        if (r.kind == RefKind.head || r.kind == RefKind.tag) RefPill(gitRef: r),
    ],
  );

  Widget _metaLine(AppTokens t, Commit c) {
    final style = TextStyle(color: t.textFaint, fontSize: 11);
    final items = <Widget>[
      if (_on('author')) Text(c.author, style: style),
      if (_on('date'))
        Text(formatCommitDate(c.date, format: dateFormat), style: style),
      if (_on('sha'))
        Text(
          c.shortSha,
          style: style.copyWith(fontFamily: 'monospace', letterSpacing: 0.3),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('·', style: style),
            ),
          items[i],
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final Commit commit;
  final double size;
  const _Avatar({required this.commit, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = commit.author.isEmpty
        ? '?'
        : commit.author.trim()[0].toUpperCase();
    return Tooltip(
      message: '${commit.author} <${commit.authorEmail}>',
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color(commit.avatarValue),
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
