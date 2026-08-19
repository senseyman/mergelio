import 'package:flutter/foundation.dart';

import 'git/models.dart';

/// How [CommitQuery.content] is handed to git's pickaxe.
enum ContentSearchMode {
  /// `git log -S`: commits that change how many times the literal string
  /// occurs. Answers "which commit introduced this?" — a commit that merely
  /// moves the line around is not reported.
  occurrences,

  /// `git log -G`: commits with an added or removed line matching the pattern
  /// as a regular expression. Wider, and the only mode that finds a string
  /// that was both added and removed in the same commit.
  diffText,
}

/// Filters applied alongside the free-text query in global search.
class CommitQuery {
  final String text;
  final String author;
  final bool hideMerges;
  final bool hideTags;

  /// Repo-relative path whose history is being followed, or empty for none.
  /// Which commits touched it cannot be told from a commit alone, so the shas
  /// are read from git separately and passed to the matchers.
  final String path;

  /// String searched for inside the commits' diffs, or empty for none. Like
  /// [path], a commit alone cannot answer this, so the shas come from git.
  final String content;

  /// How [content] is matched. Ignored while [content] is empty.
  final ContentSearchMode contentMode;
  const CommitQuery({
    this.text = '',
    this.author = '',
    this.hideMerges = false,
    this.hideTags = false,
    this.path = '',
    this.content = '',
    this.contentMode = ContentSearchMode.occurrences,
  });

  CommitQuery copyWith({
    String? text,
    String? author,
    bool? hideMerges,
    bool? hideTags,
    String? path,
    String? content,
    ContentSearchMode? contentMode,
  }) => CommitQuery(
    text: text ?? this.text,
    author: author ?? this.author,
    hideMerges: hideMerges ?? this.hideMerges,
    hideTags: hideTags ?? this.hideTags,
    path: path ?? this.path,
    content: content ?? this.content,
    contentMode: contentMode ?? this.contentMode,
  );

  bool get isEmpty =>
      text.trim().isEmpty &&
      author.isEmpty &&
      path.isEmpty &&
      content.isEmpty &&
      !hideMerges &&
      !hideTags;
}

/// True when [c] matches [q]: the free text is found (case-insensitive) in the
/// message, author, or sha; the author filter is a substring of the author;
/// merges and tag-carrying commits are excluded when requested.
///
/// [pathShas] are the commits that touched [CommitQuery.path]; [contentShas]
/// the commits whose diff matched [CommitQuery.content]. While either filter
/// is on and its shas have not arrived yet, nothing matches — better a
/// momentarily empty result than every commit claiming to be a hit.
bool matchesCommit(
  Commit c,
  CommitQuery q, {
  Set<String>? pathShas,
  Set<String>? contentShas,
}) {
  if (q.path.isNotEmpty && !(pathShas?.contains(c.sha) ?? false)) return false;
  if (q.content.isNotEmpty && !(contentShas?.contains(c.sha) ?? false)) {
    return false;
  }
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

List<Commit> searchCommits(
  List<Commit> commits,
  CommitQuery q, {
  Set<String>? pathShas,
  Set<String>? contentShas,
}) => q.isEmpty
    ? const []
    : commits
          .where(
            (c) => matchesCommit(
              c,
              q,
              pathShas: pathShas,
              contentShas: contentShas,
            ),
          )
          .toList();

/// Threshold above which match computation moves to a background isolate so a
/// keystroke on a huge (50k+) history never blocks the UI thread.
const searchIsolateThreshold = 5000;

Set<String> _matchShasSync(
  (List<Commit>, CommitQuery, Set<String>?, Set<String>?) args,
) => {
  for (final c in args.$1)
    if (matchesCommit(c, args.$2, pathShas: args.$3, contentShas: args.$4))
      c.sha,
};

/// Shas of commits matching [q]. Small lists compute synchronously (isolate
/// spawn + copy would cost more than the scan); large ones go through
/// [compute] off the UI isolate.
Future<Set<String>> computeMatchShas(
  List<Commit> commits,
  CommitQuery q, {
  Set<String>? pathShas,
  Set<String>? contentShas,
}) {
  if (q.isEmpty) return Future.value(const {});
  if (commits.length < searchIsolateThreshold) {
    return Future.value(_matchShasSync((commits, q, pathShas, contentShas)));
  }
  return compute(_matchShasSync, (commits, q, pathShas, contentShas));
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
