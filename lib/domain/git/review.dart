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

/// A short, stable digest of everything a reviewer sees in [file]. Marking a
/// file viewed records this; when head moves and the diff changes, the digest
/// no longer matches and the mark lapses, so new content is never hidden
/// behind an old tick.
String diffFingerprint(FileDiff file) {
  // 64-bit FNV-1a: cheap, no dependency, and only ever compared within one
  // session, so collision resistance against an adversary is not a concern.
  var h = 0xcbf29ce484222325;
  void add(String s) {
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    h ^= 0x1f;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }

  add(file.path);
  add(file.oldPath ?? '');
  add(file.status.name);
  add(file.binary ? 'b' : 't');
  add(file.lfs?.after?.oid ?? '');
  for (final hunk in file.hunks) {
    add(hunk.header);
    for (final line in hunk.lines) {
      add(line.type.name);
      add(line.text);
    }
  }
  return h.toUnsigned(64).toRadixString(16);
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
}) => [
  for (final b in branches) RefChoice(RefChoiceKind.branch, b.name),
  for (final r in remoteBranches)
    // `origin/HEAD` is an alias for another remote branch already listed.
    if (r.branch != 'HEAD') RefChoice(RefChoiceKind.remote, r.name),
  for (final t in tags) RefChoice(RefChoiceKind.tag, t),
  for (final w in worktrees)
    if (w.kind != WorktreeKind.bare &&
        !samePath(w.path, repoPath) &&
        (w.branch ?? w.head) != null)
      RefChoice(RefChoiceKind.worktree, w.branch ?? w.head!, detail: w.path),
];

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
