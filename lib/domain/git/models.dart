import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';

/// Kind of ref pointing at a commit. `head` is the symbolic HEAD; `local` and
/// `remote` are branches; `tag` is a tag.
enum RefKind { head, local, remote, tag }

/// A ref label shown on a commit (branch/tag/HEAD chip).
@freezed
class GitRef with _$GitRef {
  const factory GitRef({required RefKind kind, required String name}) = _GitRef;
}

/// A single change on one side (staged index or working tree) of a file.
/// `none` means unchanged on that side. Mirrors git's porcelain XY codes.
enum GitChange {
  none,
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  conflicted,
}

/// A commit as read from `git log`. Layout fields ([lane], [ci], [through],
/// [mergeFrom], [branchStart]) are zero/empty until [assignLanes] fills them;
/// the render stage consumes them. [merge] is derived from [parents].
@freezed
class Commit with _$Commit {
  const Commit._();
  const factory Commit({
    required String sha,
    required String message,
    // Commit body (everything after the subject line); empty when the commit
    // has no description. Trailing whitespace is trimmed.
    @Default('') String body,
    required String author,
    required String authorEmail,
    required DateTime date,
    @Default([]) List<String> parents,
    @Default([]) List<GitRef> refs,
    @Default(false) bool signed,
    // Raw `git log %G?` code: G good, U good-untrusted, X/Y/R expired/revoked,
    // B bad, E can't-check, N none. Drives the signature label's meaning.
    @Default('N') String sigStatus,
    @Default(false) bool coauthor,
    // Deterministic author avatar colour (ARGB), derived from the email.
    @Default(0) int avatarValue,
    // Graph layout — populated by the lane algorithm, not by the reader.
    @Default(0) int lane,
    @Default(0) int ci,
    @Default([]) List<int> through,
    int? mergeFrom,
    @Default(false) bool branchStart,
    // Lane this commit's branch merges down into (set only when branchStart).
    int? branchInto,
    // True when no child commit points here — the head of its strand, so the
    // rail draws nothing above the node.
    @Default(false) bool tip,
  }) = _Commit;

  bool get merge => parents.length > 1;
  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// A local branch with tracking info. [ahead]/[behind] are relative to its
/// upstream (0 when there is none). [ci] is its graph colour index.
@freezed
class Branch with _$Branch {
  const factory Branch({
    required String name,
    @Default(false) bool current,
    @Default(0) int ahead,
    @Default(0) int behind,
    @Default(0) int ci,
    // Sha the branch ref points at (its tip commit).
    @Default('') String tip,
    // Short upstream ref name (e.g. `origin/main`), empty when untracked.
    @Default('') String upstream,
  }) = _Branch;
}

/// A remote-tracking branch, e.g. `origin/main`. [hasLocal] is true when a
/// local branch of the same short name already exists.
@freezed
class RemoteBranch with _$RemoteBranch {
  const RemoteBranch._();
  const factory RemoteBranch({
    required String remote,
    required String branch,
    @Default(false) bool hasLocal,
    // Sha the remote-tracking ref points at.
    @Default('') String tip,
  }) = _RemoteBranch;

  String get name => '$remote/$branch';
}

/// A stash entry, e.g. `stash@{0}` with its message.
@freezed
class Stash with _$Stash {
  const factory Stash({required String ref, required String message}) = _Stash;
}

/// A working-tree file with its staged ([index]) and unstaged ([worktree])
/// change state. A file changed on both sides is "partial" and shows in both
/// STAGED and UNSTAGED lists. [origPath] is set for renames/copies.
@freezed
class WorkingFile with _$WorkingFile {
  const WorkingFile._();
  const factory WorkingFile({
    required String path,
    @Default(GitChange.none) GitChange index,
    @Default(GitChange.none) GitChange worktree,
    String? origPath,
  }) = _WorkingFile;

  bool get isStaged => index != GitChange.none;
  bool get isUnstaged => worktree != GitChange.none;
  bool get isPartial => isStaged && isUnstaged;
  bool get isUntracked => worktree == GitChange.untracked;
  bool get isConflicted =>
      index == GitChange.conflicted || worktree == GitChange.conflicted;
}

/// A file touched by a commit, as shown in the commit details panel.
/// [origPath] is set for renames/copies.
@freezed
class CommitFileChange with _$CommitFileChange {
  const factory CommitFileChange({
    required String path,
    required GitChange change,
    String? origPath,
  }) = _CommitFileChange;
}

/// A squash-merge link: the branch tip [fromSha] was squashed onto the mainline
/// at [toSha]. There is no git parent edge for this — it is inferred from tree
/// equality — so the graph draws it as a dashed connector.
@freezed
class SquashLink with _$SquashLink {
  const factory SquashLink({required String fromSha, required String toSha}) =
      _SquashLink;
}
