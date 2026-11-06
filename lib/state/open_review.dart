import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/forge/forge_host.dart';
import 'repo_actions.dart';
import 'review.dart';

typedef FetchPullRequestForReview =
    Future<({String base, String head})?> Function(
      String repoPath,
      ForgeKind kind,
      int number,
      String targetBranch,
    );

/// How a pull request's review gets the commits it reads.
///
/// Overridable so a widget test can see what would have been fetched without
/// running git on the host.
final forgeFetchPullRequestForReviewProvider =
    Provider<FetchPullRequestForReview>(
      (ref) =>
          (repoPath, kind, number, targetBranch) => ref
              .read(repoActionsProvider(repoPath))
              .fetchPullRequestForReview(kind, number, targetBranch),
    );

/// Fetches the commits of request [number] and opens its review on [review].
///
/// Takes the notifier and the fetch rather than a ref so a caller whose ref
/// may be gone by the time the fetch answers can capture both first. Returns
/// false when the fetch failed; the fetch already reported why.
Future<bool> openPullRequestReviewWith({
  required StateController<ReviewTarget?> review,
  required FetchPullRequestForReview fetch,
  required String repoPath,
  required ForgeKind kind,
  required int number,
  required String targetBranch,
}) async {
  final shas = await fetch(repoPath, kind, number, targetBranch);
  if (shas == null) return false;
  review.state = ReviewTarget(
    repoPath: repoPath,
    base: shas.base,
    head: shas.head,
    pullRequest: ReviewPullRequest(
      kind: kind,
      number: number,
      targetBranch: targetBranch,
    ),
  );
  return true;
}

/// [openPullRequestReviewWith] for state-layer callers.
Future<bool> openPullRequestReview(
  Ref ref, {
  required String repoPath,
  required ForgeKind kind,
  required int number,
  required String targetBranch,
}) => openPullRequestReviewWith(
  review: ref.read(reviewTargetProvider.notifier),
  fetch: ref.read(forgeFetchPullRequestForReviewProvider),
  repoPath: repoPath,
  kind: kind,
  number: number,
  targetBranch: targetBranch,
);
