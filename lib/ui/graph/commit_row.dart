import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'commit_columns.dart';
import 'graph_rail.dart';
import 'rail_metrics.dart';
import 'ref_pill.dart';

/// One graph row: the painted rail cell, then avatar · message · signed badge ·
/// ref pills, with a meta line (branch/author/date/sha, each toggleable) in the
/// two-line layout. Compact mode collapses to a single line.
class CommitRow extends StatelessWidget {
  final Commit commit;
  final String? branchLabel;
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
    required this.branchLabel,
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
    final firstLine = c.message.split('\n').first;

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
                SizedBox(
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
      for (final r in c.refs) RefPill(gitRef: r),
    ],
  );

  Widget _metaLine(AppTokens t, Commit c) {
    final style = TextStyle(color: t.textFaint, fontSize: 11);
    final branch = branchLabel;
    final items = <Widget>[
      if (_on('branch') && branch != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: t.branchColor(c.ci),
                shape: BoxShape.circle,
              ),
            ),
            Text(branch, style: style),
          ],
        ),
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
    return Container(
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
    );
  }
}
