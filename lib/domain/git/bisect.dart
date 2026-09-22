/// Verdict recorded against a commit during bisect.
enum BisectKind { good, bad, skip }

/// One commit's git verdict, read back from `refs/bisect/*`.
class BisectMark {
  final String sha;
  final BisectKind kind;
  const BisectMark(this.sha, this.kind);
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
List<BisectMark> parseBisectRefs(String out) {
  const kinds = {
    'bad': BisectKind.bad,
    'good': BisectKind.good,
    'skip': BisectKind.skip,
  };
  final marks = <BisectMark>[];
  for (final line in out.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final name = parts[1].replaceFirst('refs/bisect/', '');
    final kind = kinds[name.split('-').first];
    if (kind != null) {
      marks.add(BisectMark(parts[0], kind));
    }
  }
  return marks;
}

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
