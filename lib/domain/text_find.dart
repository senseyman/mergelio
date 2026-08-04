/// One occurrence of a search query, as offsets into the text it was found in.
class TextMatch {
  final int start;
  final int end;
  const TextMatch(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is TextMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextMatch($start, $end)';
}

/// Every occurrence of [query] in [text], left to right and never overlapping.
/// The query is plain text: a `.` or a `$` in it means that character, not a
/// pattern, since the find bar takes what the user typed.
List<TextMatch> findMatches(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty || text.isEmpty) return const [];
  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TextMatch>[];
  for (var at = haystack.indexOf(needle); at >= 0;) {
    matches.add(TextMatch(at, at + needle.length));
    at = haystack.indexOf(needle, at + needle.length);
  }
  return matches;
}

/// Where Next / Previous goes from [cursor]: the index into [matches] of the
/// first one at or after it, or the last one before it going backwards. Both
/// wrap, so walking a file never dead-ends. Null when nothing was found.
int? nextMatch(List<TextMatch> matches, int cursor, {bool forward = true}) {
  if (matches.isEmpty) return null;
  if (forward) {
    final at = matches.indexWhere((m) => m.start >= cursor);
    return at < 0 ? 0 : at;
  }
  final at = matches.lastIndexWhere((m) => m.start < cursor);
  return at < 0 ? matches.length - 1 : at;
}

/// [text] with every occurrence of [query] replaced by [replacement], which is
/// inserted as typed — no group references, and never searched again itself.
String replaceAllMatches(
  String text,
  String query,
  String replacement, {
  bool caseSensitive = false,
}) {
  final matches = findMatches(text, query, caseSensitive: caseSensitive);
  if (matches.isEmpty) return text;
  final out = StringBuffer();
  var at = 0;
  for (final m in matches) {
    out
      ..write(text.substring(at, m.start))
      ..write(replacement);
    at = m.end;
  }
  out.write(text.substring(at));
  return out.toString();
}

/// [text] with just [match] replaced.
String replaceMatch(String text, TextMatch match, String replacement) =>
    text.replaceRange(match.start, match.end, replacement);
