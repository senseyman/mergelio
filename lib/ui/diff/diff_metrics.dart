import 'dart:math' as math;

import '../../domain/git/diff.dart';

/// How wide the fixed chrome to the left of the code is in the inline view:
/// stage button, both line-number columns, the +/- marker and their spacing.
/// Deliberately a little generous — over-reserving costs a few idle pixels of
/// scroll range, while under-reserving clips the end of the longest line.
const kDiffGutterWidth = 120.0;

/// The same, for one half of the split view: a single line-number column and
/// the half's own padding.
const kSplitGutterWidth = 64.0;

/// Columns a tab is budgeted for. Flutter lays a tab out as a single glyph
/// rather than expanding it, so this is a reserve against under-measuring an
/// indented line, not a rendering rule.
const _tabColumns = 4;

/// Characters in the widest line the diff will render, hunk headers included.
/// The code font is monospace, so a character count stands in for a measured
/// width and no line has to be laid out to find the longest one.
int longestLineChars(List<FileDiff> files) {
  var longest = 0;
  for (final f in files) {
    for (final h in f.hunks) {
      longest = math.max(longest, _columns(h.header));
      for (final l in h.lines) {
        longest = math.max(longest, _columns(l.text));
      }
    }
  }
  return longest;
}

/// Widest line on each side of the split view. Deletions and context sit on the
/// left, additions and context on the right, so the two can differ by a lot —
/// a newly added file has nothing at all on the left. Sizing each side to its
/// own longest line is what stops an empty half from crowding out the other.
///
/// Hunk headers are counted on the left only, which is where they are drawn.
({int left, int right}) longestLineCharsPerSide(List<FileDiff> files) {
  var left = 0, right = 0;
  for (final f in files) {
    for (final h in f.hunks) {
      left = math.max(left, _columns(h.header));
      for (final l in h.lines) {
        final n = _columns(l.text);
        if (l.type != DiffLineType.add) left = math.max(left, n);
        if (l.type != DiffLineType.del) right = math.max(right, n);
      }
    }
  }
  return (left: left, right: right);
}

int _columns(String s) {
  var n = s.length;
  for (final c in s.codeUnits) {
    if (c == 0x09) n += _tabColumns - 1;
  }
  return n;
}

/// Width one scrollable diff column needs: [gutter] plus [chars] of code at
/// [charWidth] each. Never narrower than [viewport], so a short diff still
/// fills the space it is given and rows keep their full-width backgrounds.
double diffContentWidth({
  required double viewport,
  required int chars,
  required double charWidth,
  double gutter = kDiffGutterWidth,
}) {
  // Trailing slack so the last character is not flush against the edge.
  const pad = 24.0;
  return math.max(viewport, gutter + chars * charWidth + pad);
}
