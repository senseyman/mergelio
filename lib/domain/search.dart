import 'package:flutter/foundation.dart';

import 'git/models.dart';

/// Filters applied alongside the free-text query in global search.
class CommitQuery {
  final String text;
  final String author;
  final bool hideMerges;
  final bool hideTags;
  const CommitQuery({
    this.text = '',
    this.author = '',
    this.hideMerges = false,
    this.hideTags = false,
  });

  bool get isEmpty =>
      text.trim().isEmpty && author.isEmpty && !hideMerges && !hideTags;
}

/// True when [c] matches [q]: the free text is found (case-insensitive) in the
/// message, author, or sha; the author filter is a substring of the author;
/// merges and tag-carrying commits are excluded when requested.
bool matchesCommit(Commit c, CommitQuery q) {
  if (q.hideMerges && c.merge) return false;
  if (q.hideTags && c.refs.any((r) => r.kind == RefKind.tag)) return false;
  if (q.author.isNotEmpty &&
      !c.author.toLowerCase().contains(q.author.toLowerCase())) {
    return false;
  }
  final text = q.text.trim().toLowerCase();
  if (text.isEmpty) return true;
  return c.message.toLowerCase().contains(text) ||
      c.author.toLowerCase().contains(text) ||
      c.sha.toLowerCase().startsWith(text);
}

List<Commit> searchCommits(List<Commit> commits, CommitQuery q) =>
    q.isEmpty ? const [] : commits.where((c) => matchesCommit(c, q)).toList();

/// Threshold above which match computation moves to a background isolate so a
/// keystroke on a huge (50k+) history never blocks the UI thread.
const searchIsolateThreshold = 5000;

Set<String> _matchShasSync((List<Commit>, CommitQuery) args) => {
  for (final c in args.$1)
    if (matchesCommit(c, args.$2)) c.sha,
};

/// Shas of commits matching [q]. Small lists compute synchronously (isolate
/// spawn + copy would cost more than the scan); large ones go through
/// [compute] off the UI isolate.
Future<Set<String>> computeMatchShas(List<Commit> commits, CommitQuery q) {
  if (q.isEmpty) return Future.value(const {});
  if (commits.length < searchIsolateThreshold) {
    return Future.value(_matchShasSync((commits, q)));
  }
  return compute(_matchShasSync, (commits, q));
}

/// Case-insensitive subsequence fuzzy score for the command palette. Returns
/// null when [pattern] is not a subsequence of [text]; otherwise a score where
/// higher is better — contiguous runs and start-of-word matches score more.
int? fuzzyScore(String pattern, String text) {
  if (pattern.isEmpty) return 0;
  final p = pattern.toLowerCase();
  final t = text.toLowerCase();
  var score = 0;
  var ti = 0;
  var prevMatch = -2;
  for (var pi = 0; pi < p.length; pi++) {
    final ch = p[pi];
    final found = t.indexOf(ch, ti);
    if (found < 0) return null;
    score += 1;
    if (found == prevMatch + 1) score += 3; // contiguous
    if (found == 0 || !_isWordChar(t[found - 1])) score += 2; // word start
    prevMatch = found;
    ti = found + 1;
  }
  return score;
}

bool _isWordChar(String c) => RegExp(r'[A-Za-z0-9]').hasMatch(c);

/// Ranks [items] by fuzzy match of [pattern] against each item's label
/// ([labelOf]); non-matches are dropped, best first.
List<T> fuzzyRank<T>(
  String pattern,
  List<T> items,
  String Function(T) labelOf,
) {
  final scored = <(int, T)>[];
  for (final item in items) {
    final s = fuzzyScore(pattern, labelOf(item));
    if (s != null) scored.add((s, item));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final e in scored) e.$2];
}
