import 'dart:math' as math;

import '../../domain/git/diff.dart';

/// How wide the fixed chrome to the left of the code is: stage button, both
/// line-number columns, the +/- marker and their spacing. Deliberately a
/// little generous — over-reserving costs a few idle pixels of scroll range,
/// while under-reserving clips the end of the longest line.
const kDiffGutterWidth = 120.0;

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

int _columns(String s) {
  var n = s.length;
  for (final c in s.codeUnits) {
    if (c == 0x09) n += _tabColumns - 1;
  }
  return n;
}

/// Width the scrollable diff content needs: the gutter plus [chars] of code at
/// [charWidth] each, doubled for split view because both sides sit on the same
/// row. Never narrower than [viewport], so a short diff still fills the sheet
/// and rows keep their full-width backgrounds.
double diffContentWidth({
  required double viewport,
  required int chars,
  required double charWidth,
  required bool split,
}) {
  // Trailing slack so the last character is not flush against the edge.
  const pad = 24.0;
  final oneSide = kDiffGutterWidth + chars * charWidth + pad;
  return math.max(viewport, split ? oneSide * 2 : oneSide);
}
