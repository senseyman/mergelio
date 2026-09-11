import '../domain/git/models.dart';

/// Runs the squash-link inference for [branches], measured against [into].
typedef SquashLinkCompute =
    Future<List<SquashLink>> Function(List<Branch> branches, String into);

/// Keeps squash-merge inference proportional to what changed.
///
/// Inferring one branch's link costs about five git subprocesses, so asking
/// about every branch on every refresh is what makes a repository with a lot of
/// branches feel slow — creating a branch is a few milliseconds of git followed
/// by seconds of re-inference.
///
/// Two properties of the inference make the saving safe. A branch's link
/// depends on that branch's tip and on the commit the current branch points at,
/// never on any other branch, so a branch that has not moved keeps its answer.
/// And the current branch enters only as a revision — the inference resolves it
/// to a commit and never looks at the name — so checking out a different branch
/// that sits on the same commit cannot change the result, which is exactly the
/// state that creating a branch and switching to it leaves behind.
class SquashLinkCache {
  /// Per repository: the tip everything was measured against, and each
  /// branch's answer under its own tip. A null value is an answer too — the
  /// branch was inferred and has no link.
  final _byRepo =
      <String, ({String intoTip, Map<String, SquashLink?> links})>{};

  /// Drops what is remembered for [path], so the next resolve infers again.
  void forget(String path) => _byRepo.remove(path);

  Future<List<SquashLink>> resolve({
    required String path,
    required List<Branch> branches,
    required SquashLinkCompute compute,
  }) async {
    final current = branches.where((b) => b.current);
    if (current.isEmpty) return const [];
    final into = current.first;

    final previous = _byRepo[path];
    final links = previous != null && previous.intoTip == into.tip
        ? previous.links
        : <String, SquashLink?>{};

    final missing = [
      for (final b in branches)
        if (!links.containsKey(b.tip)) b,
    ];
    if (missing.isNotEmpty) {
      final fresh = await compute(missing, into.name);
      final byTip = {for (final l in fresh) l.fromSha: l};
      for (final b in missing) {
        links[b.tip] = byTip[b.tip];
      }
    }

    // Branches that are gone stop being carried: without this the map would
    // grow for as long as the session lasts on a repository with churn.
    final live = {for (final b in branches) b.tip};
    links.removeWhere((tip, _) => !live.contains(tip));

    _byRepo[path] = (intoTip: into.tip, links: links);

    // Several branches can share a tip; each link belongs in the answer once.
    final seen = <String>{};
    return [
      for (final b in branches)
        if (links[b.tip] case final link?)
          if (seen.add(b.tip)) link,
    ];
  }
}
