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

  /// First and last day the commit may have been authored on, inclusive. Only
  /// the date part counts. Null leaves that end open.
  final DateTime? since;
  final DateTime? until;
  const CommitQuery({
    this.text = '',
    this.author = '',
    this.hideMerges = false,
    this.hideTags = false,
    this.path = '',
    this.content = '',
    this.contentMode = ContentSearchMode.occurrences,
    this.since,
    this.until,
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
    since: since,
    until: until,
  );

  /// This query with its date range replaced; null clears that end, which
  /// [copyWith] cannot express.
  CommitQuery withDates(DateTime? since, DateTime? until) => CommitQuery(
    text: text,
    author: author,
    hideMerges: hideMerges,
    hideTags: hideTags,
    path: path,
    content: content,
    contentMode: contentMode,
    since: since,
    until: until,
  );

  /// True when the author or the date range is set. Those two are answered by
  /// git over the whole history rather than by the loaded commits, so the
  /// author matches the email as well as the name, and a match past the
  /// loaded page is still known about.
  bool get hasHistoryFilter =>
      author.trim().isNotEmpty || since != null || until != null;

  bool get isEmpty =>
      text.trim().isEmpty &&
      !hasHistoryFilter &&
      path.isEmpty &&
      content.isEmpty &&
      !hideMerges &&
      !hideTags;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// True when [authored] falls on or between the days of [since] and [until];
/// an open end does not limit.
bool authoredWithin(DateTime authored, DateTime? since, DateTime? until) {
  if (since != null && authored.isBefore(_day(since))) return false;
  if (until != null) {
    final end = _day(until);
    if (!authored.isBefore(DateTime(end.year, end.month, end.day + 1))) {
      return false;
    }
  }
  return true;
}

/// `git log` arguments listing every commit's sha and author time for the
/// history filter. The date range itself is applied to the author time
/// afterwards, by [authoredWithin]: git's own `--since`/`--until` compare the
/// committer date, which a rebase moves away from the date the graph shows.
///
/// [stashes] are walked as extra revisions, as the graph walks them: only the
/// newest stash is reachable from a ref.
List<String> historyFilterArgs(
  String author,
  DateTime? since, {
  bool noMerges = false,
  List<String> stashes = const [],
}) {
  final a = author.trim();
  return [
    'log',
    // The graph draws every branch, so the filter walks every branch too.
    '--all',
    // With mailmap on, git matches the mapped identity while the graph shows
    // the one recorded in the commit, and a name on screen would find nothing.
    '--no-use-mailmap',
    '--format=%H%x00%at',
    if (a.isNotEmpty) ...[
      '-i',
      // Literal, so a name like "Bob (dev)" is not read as a pattern.
      '-F',
      // Glued to the flag so an author starting with `-` is not an option.
      '--author=$a',
    ],
    // Only a pre-filter, letting git stop the walk early. It drops nothing
    // the author-date check would keep as long as no commit was committed
    // before it was authored, which only a clock running ahead on the
    // author's machine breaks; covering that would cost a walk of the whole
    // history for every date search. No `--until`: a commit authored before
    // the end may well have been committed after it.
    //
    // Written as a local date rather than `@<seconds>`: git takes a number
    // for a timestamp only when it is long enough, so a date before the
    // early seventies would have become some other cutoff.
    if (since != null) '--since=${_isoDay(since)} 00:00:00',
    if (noMerges) '--no-merges',
    ...stashes,
  ];
}

/// True when [c] matches [q]: the free text is found (case-insensitive) in the
/// message, author, or sha; merges and tag-carrying commits are excluded when
/// requested.
///
/// [pathShas] are the commits that touched [CommitQuery.path]; [contentShas]
/// the commits whose diff matched [CommitQuery.content]; [historyShas] the
/// commits git reported for the author and date range. While any of those
/// filters is on and its shas have not arrived yet, nothing matches — better
/// a momentarily empty result than every commit claiming to be a hit.
bool matchesCommit(
  Commit c,
  CommitQuery q, {
  Set<String>? pathShas,
  Set<String>? contentShas,
  Set<String>? historyShas,
}) {
  if (q.path.isNotEmpty && !(pathShas?.contains(c.sha) ?? false)) return false;
  if (q.content.isNotEmpty && !(contentShas?.contains(c.sha) ?? false)) {
    return false;
  }
  if (q.hasHistoryFilter && !(historyShas?.contains(c.sha) ?? false)) {
    return false;
  }
  if (q.hideMerges && c.merge) return false;
  if (q.hideTags && c.refs.any((r) => r.kind == RefKind.tag)) return false;
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
  Set<String>? historyShas,
}) => q.isEmpty
    ? const []
    : commits
          .where(
            (c) => matchesCommit(
              c,
              q,
              pathShas: pathShas,
              contentShas: contentShas,
              historyShas: historyShas,
            ),
          )
          .toList();

/// How many commits git reported for the history filter that are not among
/// [loaded] yet — matches the graph would show after paging in more history.
/// When a path or content filter is on, its shas have to agree too. The other
/// filters need the commit itself, so this is an upper bound.
int olderMatchCount(
  Iterable<Commit> loaded,
  Set<String> historyShas, {
  Set<String>? pathShas,
  Set<String>? contentShas,
}) {
  final have = {for (final c in loaded) c.sha};
  return historyShas
      .where(
        (s) =>
            !have.contains(s) &&
            (pathShas?.contains(s) ?? true) &&
            (contentShas?.contains(s) ?? true),
      )
      .length;
}

/// Threshold above which match computation moves to a background isolate so a
/// keystroke on a huge (50k+) history never blocks the UI thread.
const searchIsolateThreshold = 5000;

Set<String> _matchShasSync(
  (List<Commit>, CommitQuery, Set<String>?, Set<String>?, Set<String>?) args,
) => {
  for (final c in args.$1)
    if (matchesCommit(
      c,
      args.$2,
      pathShas: args.$3,
      contentShas: args.$4,
      historyShas: args.$5,
    ))
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
  Set<String>? historyShas,
}) {
  if (q.isEmpty) return Future.value(const {});
  final args = (commits, q, pathShas, contentShas, historyShas);
  if (commits.length < searchIsolateThreshold) {
    return Future.value(_matchShasSync(args));
  }
  return compute(_matchShasSync, args);
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
