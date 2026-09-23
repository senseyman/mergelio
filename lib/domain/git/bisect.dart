/// Verdict recorded against a commit during bisect.
enum BisectKind { good, bad, skip }

/// One commit's git verdict, read back from `refs/bisect/*`.
class BisectMark {
  final String sha;
  final BisectKind kind;
  const BisectMark(this.sha, this.kind);
}

extension on List<BisectMark> {
  /// The first mark of [kind], or null when there is none. Bisect keeps one
  /// bad end at a time, so for that kind "first" is the only one there is.
  BisectMark? firstOfKind(BisectKind kind) =>
      where((m) => m.kind == kind).firstOrNull;
}

/// Word pair that bisect uses. Git defaults to good/bad but lets a
/// repository pick its own (old/new for a bisect that hunts a fix rather
/// than a break). The command shows the repository's own words.
class BisectTerms {
  final String good;
  final String bad;
  const BisectTerms({this.good = 'good', this.bad = 'bad'});
}

/// Parse marks from `for-each-ref --format='%(objectname) %(refname)' refs/bisect`.
///
/// Marks extract the sha (target of the ref) and the type from refs like
/// `refs/bisect/bad`, `refs/bisect/good-<sha>`. The sha in both the target
/// and the name suffix agree, but the target is what the ref actually points
/// at; that is the one to trust. Refs that match no known verdict are skipped;
/// a future git version adding one must not break the rest.
///
/// Git names those refs after [terms], so a repository that renamed its ends
/// has none called good or bad — pass the terms read from the repository or
/// every mark it holds reads as nothing at all.
List<BisectMark> parseBisectRefs(
  String out, [
  BisectTerms terms = const BisectTerms(),
]) {
  final marks = <BisectMark>[];
  for (final line in out.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final kind = _kindOfRef(parts[1].replaceFirst('refs/bisect/', ''), terms);
    if (kind != null) {
      marks.add(BisectMark(parts[0], kind));
    }
  }
  return marks;
}

/// The verdict a `refs/bisect/*` name records, or null when it records none.
///
/// The bad end is a bare ref name, the good end and skips carry a `-<sha>`
/// suffix. Matching whole words against the terms rather than cutting the name
/// at its first hyphen keeps terms that contain one (`known-good`) readable.
BisectKind? _kindOfRef(String name, BisectTerms terms) {
  // Skip is a subcommand rather than a term, so git never renames it.
  if (_namesTerm(name, 'skip')) return BisectKind.skip;
  if (_namesTerm(name, terms.bad)) return BisectKind.bad;
  if (_namesTerm(name, terms.good)) return BisectKind.good;
  return null;
}

bool _namesTerm(String name, String term) =>
    name == term || name.startsWith('$term-');

/// Parse BISECT_TERMS: `bad_word\ngood_word`.
///
/// Git stores bisect's term names in `.git/BISECT_TERMS` as two lines:
/// the bad term and the good term. Defaults to 'bad' and 'good'.
BisectTerms parseBisectTerms(String? contents) {
  final lines = (contents ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length < 2) return const BisectTerms();
  return BisectTerms(bad: lines[0], good: lines[1]);
}

/// Counts from `rev-list --bisect-vars`. A count of -1 means git was never
/// asked — the range had no endpoints yet — which is not the same as a range
/// that has narrowed to nothing.
class BisectVars {
  final String rev;
  final int nr;
  final int steps;
  const BisectVars({this.rev = '', this.nr = -1, this.steps = -1});
}

/// `rev-list --bisect-vars` emits shell assignments, one per line, and adds
/// new ones over time; only these three are read and the rest are ignored.
BisectVars parseBisectVars(String out) {
  var rev = '';
  var nr = -1;
  var steps = -1;
  for (final line in out.split('\n')) {
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    // Some values arrive single-quoted, some bare.
    final value = line.substring(eq + 1).trim().replaceAll("'", '');
    switch (key) {
      case 'bisect_rev':
        rev = value;
      case 'bisect_nr':
        nr = int.tryParse(value) ?? -1;
      case 'bisect_steps':
        steps = int.tryParse(value) ?? -1;
    }
  }
  return BisectVars(rev: rev, nr: nr, steps: steps);
}

/// Range arguments for `rev-list --bisect-vars`: the bad commit, then every
/// good commit behind `--not`.
///
/// Returns empty when either end is missing. Git cannot size a range with only
/// one end, and running the command anyway would walk the entire history.
/// Skips are verdicts, not endpoints, so they never appear here.
List<String> bisectVarsArgs(List<BisectMark> marks) {
  final bad = marks.firstOfKind(BisectKind.bad);
  final good = marks.where((m) => m.kind == BisectKind.good);
  if (bad == null || good.isEmpty) return const [];
  return [bad.sha, '--not', for (final g in good) g.sha];
}

/// The commit that introduced the breakage, or null while the hunt continues.
///
/// When the candidate range has narrowed to nothing, the commit still marked
/// bad is by definition the first bad one — that is the answer a bisect exists
/// to produce.
String? firstBadFrom(List<BisectMark> marks, int revisionsLeft) {
  if (revisionsLeft != 0) return null;
  return marks.firstOfKind(BisectKind.bad)?.sha;
}

/// The word that follows `git bisect` for [kind].
///
/// Good and bad are terms, and a repository may rename them. Skip is a
/// subcommand and is never renamed — spelling it as a term yields a command
/// git rejects.
String bisectCommandFor(BisectKind kind, BisectTerms terms) => switch (kind) {
  BisectKind.good => terms.good,
  BisectKind.bad => terms.bad,
  BisectKind.skip => 'skip',
};

/// A bisect as it currently stands, assembled from git's own state files.
class BisectState {
  final List<BisectMark> marks;

  /// Branch the bisect started from, restored by a reset.
  final String startBranch;
  final BisectTerms terms;

  /// The commit checked out for testing right now.
  final String currentSha;

  /// Candidates left and the steps they imply, or -1 before git has both ends
  /// of the range and can count.
  final int revisionsLeft;
  final int steps;

  final String? firstBad;

  const BisectState({
    required this.marks,
    required this.startBranch,
    required this.terms,
    required this.currentSha,
    required this.revisionsLeft,
    required this.steps,
    required this.firstBad,
  });

  /// A bad commit is known but no good one is, so git has nothing to halve and
  /// no candidate to offer.
  bool get awaitingGood =>
      marks.any((m) => m.kind == BisectKind.bad) &&
      !marks.any((m) => m.kind == BisectKind.good);

  bool get finished => firstBad != null;

  bool get running => !finished;

  /// Verdict recorded for [sha], or null when it has none.
  BisectKind? kindOf(String sha) =>
      marks.where((m) => m.sha == sha).firstOrNull?.kind;
}
