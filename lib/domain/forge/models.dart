import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';

/// Where a pull request or merge request stands. A draft is an open request
/// its author has marked not-ready; the forges model that as a flag, and it is
/// collapsed here because it reads as its own state.
enum PullRequestState { open, draft, merged, closed }

enum IssueState { open, closed }

/// One CI job's outcome. [unknown] is what a state this version does not
/// recognise becomes: a forge adding one must not crash a running client, and
/// must not be reported as passing.
enum CheckState {
  queued,
  running,
  success,
  failure,
  cancelled,
  skipped,
  unknown,
}

/// What the CI for a commit amounts to, once every job is taken together.
enum ChecksOverall { none, running, success, failure, mixed }

/// Someone on a forge. Display names are optional and frequently absent.
@freezed
abstract class ForgeUser with _$ForgeUser {
  const ForgeUser._();
  const factory ForgeUser({
    required String login,
    @Default('') String displayName,
    @Default('') String avatarUrl,
  }) = _ForgeUser;

  /// The name to put on screen: whichever of the two the forge actually has.
  String get shown => displayName.isEmpty ? login : displayName;
}

/// A pull request on GitHub or a merge request on GitLab.
@freezed
abstract class PullRequest with _$PullRequest {
  const factory PullRequest({
    /// The number a human sees and a URL carries — GitHub's `number`, GitLab's
    /// `iid`. GitLab's global `id` is a different number that addresses a
    /// different request, and must never be used here.
    required int number,
    required String title,
    required PullRequestState state,
    required ForgeUser author,
    required String sourceBranch,
    required String targetBranch,

    /// Commit at the head of the source branch. CI is fetched separately and
    /// keyed by this, so a request list and a branch badge asking about the
    /// same commit share one answer.
    required String headSha,
    DateTime? updatedAt,
  }) = _PullRequest;
}

@freezed
abstract class Issue with _$Issue {
  const factory Issue({
    required int number,
    required String title,
    required IssueState state,
    required ForgeUser author,
    @Default(<String>[]) List<String> labels,
    DateTime? updatedAt,
  }) = _Issue;
}

/// One CI job. [detailsHint] is whatever short explanation the forge offered,
/// and may be empty.
@freezed
abstract class CheckRun with _$CheckRun {
  const factory CheckRun({
    required String name,
    required CheckState state,
    @Default('') String detailsHint,
  }) = _CheckRun;
}

/// Every CI job for one commit, plus what they add up to.
@freezed
abstract class ChecksSummary with _$ChecksSummary {
  const ChecksSummary._();
  const factory ChecksSummary({
    required ChecksOverall overall,
    @Default(<CheckRun>[]) List<CheckRun> runs,
  }) = _ChecksSummary;

  /// Derives the overall state from [runs].
  ///
  /// Order matters: a failure outranks work still in progress, because a red
  /// job is actionable before the rest finish. Anything that is neither a
  /// success nor a failure nor in progress — skipped, cancelled, or a state
  /// this version does not know — leaves the result mixed rather than green,
  /// so an unrecognised outcome is never reported as passing.
  factory ChecksSummary.from(List<CheckRun> runs) {
    if (runs.isEmpty) {
      return const ChecksSummary(overall: ChecksOverall.none);
    }
    final states = runs.map((r) => r.state).toList(growable: false);
    final ChecksOverall overall;
    if (states.contains(CheckState.failure)) {
      overall = ChecksOverall.failure;
    } else if (states.contains(CheckState.queued) ||
        states.contains(CheckState.running)) {
      overall = ChecksOverall.running;
    } else if (states.every((s) => s == CheckState.success)) {
      overall = ChecksOverall.success;
    } else {
      overall = ChecksOverall.mixed;
    }
    return ChecksSummary(overall: overall, runs: runs);
  }
}
