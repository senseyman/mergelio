import '../forge/models.dart';
import '../path_key.dart';
import 'diff.dart';
import 'models.dart';
import 'worktree.dart';

/// How far apart two revisions are: [behind] counts commits only base has,
/// [ahead] commits only head has.
typedef AheadBehind = ({int behind, int ahead});

/// Parses `git rev-list --left-right --count base...head`, which prints the
/// left (base-only) count, a tab, then the right (head-only) count.
AheadBehind parseLeftRightCount(String out) {
  final parts = out.trim().split(RegExp(r'\s+'));
  if (parts.length != 2) {
    throw FormatException('expected two counts', out);
  }
  final left = int.tryParse(parts[0]);
  final right = int.tryParse(parts[1]);
  if (left == null || right == null) {
    throw FormatException('expected two counts', out);
  }
  return (behind: left, ahead: right);
}

/// The git range a review reads, as the user would type it. Three dots diff
/// head against the point it branched from base; two dots diff the two tips
/// directly. Shown in the UI so the choice is never a silent one.
String reviewRange(String base, String head, {required bool threeDot}) =>
    threeDot ? '$base...$head' : '$base..$head';

/// One changed file of a review, as git's raw and numstat listings describe
/// it — enough to draw the card and count the change without reading the diff
/// itself, which is fetched only when the card is first shown.
class ReviewFile {
  final CommitFileChange change;

  /// Both sides' blob ids and modes. Marking a file viewed records this; when
  /// head moves and the file's content changes, it no longer matches and the
  /// mark lapses, so new content is never hidden behind an old tick.
  final String fingerprint;
  final int adds;
  final int dels;

  /// git could not count lines because either side is binary.
  final bool binary;

  const ReviewFile({
    required this.change,
    required this.fingerprint,
    this.adds = 0,
    this.dels = 0,
    this.binary = false,
  });

  /// Changed lines, the measure for starting a huge diff collapsed.
  int get lines => adds + dels;
}

/// Parses `git diff --raw --no-abbrev -z` and `git diff --numstat -z`, both run
/// with the same rename detection over the same pair, into one list in raw's
/// order. A file numstat did not report still lists, uncounted.
List<ReviewFile> parseReviewFiles({
  required String raw,
  required String numstat,
}) {
  final counts = <String, ({int adds, int dels, bool binary})>{};
  final nt = numstat.split('\x00');
  for (var i = 0; i < nt.length; i++) {
    final f = nt[i].split('\t');
    if (f.length != 3) continue;
    // A rename leaves the path field empty; the old and new names follow as
    // their own records.
    String? path = f[2];
    if (path.isEmpty) {
      if (i + 2 >= nt.length) break;
      path = nt[i + 2];
      i += 2;
    }
    final binary = f[0] == '-' && f[1] == '-';
    counts[path] = (
      adds: int.tryParse(f[0]) ?? 0,
      dels: int.tryParse(f[1]) ?? 0,
      binary: binary,
    );
  }

  final out = <ReviewFile>[];
  final rt = raw.split('\x00');
  var i = 0;
  while (i + 1 < rt.length && rt[i].startsWith(':')) {
    // :<old mode> <new mode> <old blob> <new blob> <status>
    final meta = rt[i].substring(1).split(' ');
    if (meta.length != 5 || meta[4].isEmpty) break;
    final status = meta[4][0];
    final twoPaths = status == 'R' || status == 'C';
    if (twoPaths && i + 2 >= rt.length) break;
    final path = twoPaths ? rt[i + 2] : rt[i + 1];
    final origPath = twoPaths ? rt[i + 1] : null;
    i += twoPaths ? 3 : 2;
    final change = switch (status) {
      'A' => GitChange.added,
      'D' => GitChange.deleted,
      'R' => GitChange.renamed,
      'C' => GitChange.copied,
      _ => GitChange.modified,
    };
    final c = counts[path];
    out.add(
      ReviewFile(
        change: CommitFileChange(
          path: path,
          change: change,
          origPath: origPath,
        ),
        fingerprint: meta.sublist(0, 4).join(':'),
        adds: c?.adds ?? 0,
        dels: c?.dels ?? 0,
        binary: c?.binary ?? false,
      ),
    );
  }
  return out;
}

enum RefChoiceKind { branch, remote, tag, worktree }

/// One revision the review picker offers. [rev] is what git is asked for;
/// [detail] is extra context for the row, such as a worktree's location.
class RefChoice {
  final RefChoiceKind kind;
  final String rev;
  final String? detail;
  const RefChoice(this.kind, this.rev, {this.detail});
}

/// Everything a review side can be picked from, in the order the picker shows
/// it. A linked worktree contributes the commit it has checked out — by
/// branch name when it is on one — but not its uncommitted edits, which have
/// no revision to diff against. The worktree the repository is opened from is
/// left out: its branch is already in the list.
List<RefChoice> reviewRefChoices({
  required String repoPath,
  required List<Branch> branches,
  required List<RemoteBranch> remoteBranches,
  required List<String> tags,
  required List<Worktree> worktrees,
}) {
  final linked = [
    for (final w in worktrees)
      if (w.kind != WorktreeKind.bare &&
          !samePath(w.path, repoPath) &&
          (w.branch ?? w.head) != null)
        w,
  ];
  // A worktree on a local branch is that branch: one row, saying where it is
  // checked out, rather than the same revision listed twice.
  final checkedOut = {
    for (final w in linked)
      if (w.branch != null) w.branch!: w.path,
  };
  final locals = {for (final b in branches) b.name};
  return [
    for (final b in branches)
      RefChoice(RefChoiceKind.branch, b.name, detail: checkedOut[b.name]),
    for (final r in remoteBranches)
      // `origin/HEAD` is an alias for another remote branch already listed.
      if (r.branch != 'HEAD') RefChoice(RefChoiceKind.remote, r.name),
    for (final t in tags) RefChoice(RefChoiceKind.tag, t),
    for (final w in linked)
      if (w.branch == null || !locals.contains(w.branch))
        RefChoice(RefChoiceKind.worktree, w.branch ?? w.head!, detail: w.path),
  ];
}

/// The branch name a forge would know [rev] by: a local branch as is, a
/// remote-tracking branch without its remote. Null for anything else — a
/// tag or a sha has no pull request.
String? prBranchFor(
  String rev, {
  required List<String> localBranches,
  required List<String> remotes,
}) {
  if (localBranches.contains(rev)) return rev;
  for (final remote in remotes) {
    final prefix = '$remote/';
    if (rev.startsWith(prefix) && rev.length > prefix.length) {
      return rev.substring(prefix.length);
    }
  }
  return null;
}

/// The one pull request a review of a branch corresponds to. With several open
/// against different targets, the one aimed at [baseBranch] wins; if none is,
/// there is no single answer and none is offered rather than a guess.
PullRequest? pickPullRequest(List<PullRequest> prs, String? baseBranch) {
  final onBase = [
    for (final pr in prs)
      if (baseBranch != null && pr.targetBranch == baseBranch) pr,
  ];
  if (onBase.length == 1) return onBase.single;
  if (prs.length == 1) return prs.single;
  return null;
}

/// Line count past which a file's diff starts collapsed: rendering every line
/// of a generated or vendored file up front would bury the files around it.
const kReviewLargeDiffLines = 1500;

/// Whether a review file card shows its diff. [choice] is the reader's own
/// expand/collapse for this file and always wins; otherwise a viewed file is
/// put away and a very large one waits to be asked for.
bool reviewFileExpanded({
  bool? choice,
  required bool viewed,
  required int lineCount,
}) => choice ?? (!viewed && lineCount <= kReviewLargeDiffLines);

/// Where a diff line's history is read from. Lines head still has are found
/// on head by their new number; a removed line exists only on the side it was
/// removed from, under the name the file had there.
({String path, int line, String rev})? lineHistoryAnchor(
  DiffLine line, {
  required String path,
  String? oldPath,
  required String headRev,
  required String fromRev,
}) {
  if (line.type == DiffLineType.del) {
    final n = line.oldNo;
    return n == null ? null : (path: oldPath ?? path, line: n, rev: fromRev);
  }
  final n = line.newNo;
  return n == null ? null : (path: path, line: n, rev: headRev);
}

/// Branch names commonly used as a repository's trunk, most usual first.
const _trunks = ['main', 'master', 'trunk', 'develop'];

/// The sides a fresh review starts from: the checked-out branch as head,
/// against the first trunk-like branch that exists locally, else on a remote.
/// No base is suggested when none is found, or when head is the trunk itself —
/// a guess there would review a branch against itself.
({String? base, String? head}) defaultReviewSides(
  List<Branch> branches, {
  List<RemoteBranch> remoteBranches = const [],
}) {
  final head = branches.where((b) => b.current).firstOrNull?.name;
  final locals = {for (final b in branches) b.name};
  String? base;
  for (final name in _trunks) {
    if (locals.contains(name)) {
      base = name;
      break;
    }
  }
  if (base == null) {
    for (final name in _trunks) {
      final r = remoteBranches.where((r) => r.branch == name).firstOrNull;
      if (r != null) {
        base = r.name;
        break;
      }
    }
  }
  return (base: base == head ? null : base, head: head);
}
