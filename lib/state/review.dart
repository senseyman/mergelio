import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/forge/forge.dart';
import '../domain/forge/forge_host.dart';
import '../domain/forge/models.dart';
import '../domain/git/diff.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/models.dart';
import '../domain/git/review.dart';
import 'compare_target.dart';
import 'forge.dart';
import 'repo_data.dart';

/// The request a review was opened from. The review's sides are then the
/// commits fetched for it, and this is what names them and what the request's
/// description and CI are read by.
class ReviewPullRequest {
  final ForgeKind kind;
  final int number;

  /// The branch the request asks to merge into, as the forge named it.
  final String targetBranch;

  const ReviewPullRequest({
    required this.kind,
    required this.number,
    required this.targetBranch,
  });

  /// `#7` on GitHub, `!7` on GitLab — what each forge calls it in text.
  String get label => switch (kind) {
    ForgeKind.github => '#$number',
    ForgeKind.gitlab => '!$number',
  };

  @override
  bool operator ==(Object other) =>
      other is ReviewPullRequest &&
      other.kind == kind &&
      other.number == number &&
      other.targetBranch == targetBranch;

  @override
  int get hashCode => Object.hash(kind, number, targetBranch);
}

/// A branch review: what [head] brings relative to [base]. [threeDot] reads
/// head against the point it branched from base — what a pull request shows —
/// rather than against base's tip.
class ReviewTarget {
  final String repoPath;
  final String base;
  final String head;
  final bool threeDot;

  /// Set when the review shows a pull request rather than two local refs.
  final ReviewPullRequest? pullRequest;

  const ReviewTarget({
    required this.repoPath,
    required this.base,
    required this.head,
    this.threeDot = true,
    this.pullRequest,
  });

  String get baseLabel => pullRequest?.targetBranch ?? compareRefLabel(base);
  String get headLabel => pullRequest?.label ?? compareRefLabel(head);

  /// The git range this review reads, as the user would type it.
  String get range => reviewRange(baseLabel, headLabel, threeDot: threeDot);

  /// Base and head exchanged. A request does not come along: base read
  /// against the request is not what the request proposes, so its
  /// description and CI would describe something no longer on screen.
  ReviewTarget get swapped => ReviewTarget(
    repoPath: repoPath,
    base: head,
    head: base,
    threeDot: threeDot,
  );

  ReviewTarget withThreeDot(bool threeDot) => ReviewTarget(
    repoPath: repoPath,
    base: base,
    head: head,
    threeDot: threeDot,
    pullRequest: pullRequest,
  );

  @override
  bool operator ==(Object other) =>
      other is ReviewTarget &&
      other.repoPath == repoPath &&
      other.base == base &&
      other.head == head &&
      other.threeDot == threeDot &&
      other.pullRequest == pullRequest;

  @override
  int get hashCode => Object.hash(repoPath, base, head, threeDot, pullRequest);
}

/// The open review, or null when the centre column shows the graph.
final reviewTargetProvider = StateProvider<ReviewTarget?>((_) => null);

/// Everything a review shows above its file diffs, read in one go so the
/// numbers all describe the same pair of commits.
class ReviewSummary {
  final String baseSha;
  final String headSha;

  /// Where base and head forked, or null when their histories never meet.
  final String? mergeBase;

  /// What the file diffs are read from: the merge base for three dots, base's
  /// tip for two. Null when three dots were asked for and there is no merge
  /// base — there is then no honest answer, and the review says so.
  final String? fromRev;
  final AheadBehind counts;
  final List<Commit> commits;
  final bool commitsTruncated;
  final List<ReviewFile> files;

  const ReviewSummary({
    required this.baseSha,
    required this.headSha,
    required this.mergeBase,
    required this.fromRev,
    required this.counts,
    required this.commits,
    required this.commitsTruncated,
    required this.files,
  });
}

/// Reads a review. Both sides are resolved to commits first and every later
/// read uses those, so a ref moving halfway through cannot mix two states.
final reviewSummaryProvider = FutureProvider.family
    .autoDispose<ReviewSummary, ReviewTarget>((ref, target) async {
      followRefMoves(
        ref,
        repoPath: target.repoPath,
        from: target.base,
        to: target.head,
      );
      final reader = GitReader(ref.watch(gitServiceProvider), target.repoPath);
      final [baseSha, headSha] = await Future.wait([
        reader.resolveCommit(target.base),
        reader.resolveCommit(target.head),
      ]);
      final mergeBase = await reader.mergeBase(baseSha, headSha);
      final fromRev = target.threeDot ? mergeBase : baseSha;
      // Sequential: each is quick, and a failure surfaces as itself rather
      // than wrapped in a ParallelWaitError.
      final counts = await reader.aheadBehind(baseSha, headSha);
      final page = await reader.rangeCommits(baseSha, headSha);
      final files = fromRev == null
          ? const <ReviewFile>[]
          : await reader.reviewFiles(fromRev, headSha);
      return ReviewSummary(
        baseSha: baseSha,
        headSha: headSha,
        mergeBase: mergeBase,
        fromRev: fromRev,
        counts: counts,
        commits: page.commits,
        commitsTruncated: page.truncated,
        files: files,
      );
    });

/// One file of a review, between two resolved commits.
typedef ReviewFileKey = ({
  String repoPath,
  String from,
  String to,
  String path,
  String? origPath,
});

/// The parsed diff of one review file, or null when git printed none. Read on
/// its own, by pathspec, only once the file's card is shown — a wide review
/// never holds every file's text at once. Both sides are object names, so the
/// answer never goes stale and needs no ref-following.
final reviewFileDiffProvider = FutureProvider.family
    .autoDispose<FileDiff?, ReviewFileKey>((ref, key) async {
      final reader = GitReader(ref.watch(gitServiceProvider), key.repoPath);
      final raw = await reader.compareDiff(
        key.from,
        key.to,
        key.path,
        origPath: key.origPath,
      );
      return parseUnifiedDiff(raw).firstOrNull;
    });

/// Whether [path] is marked viewed for exactly the diff [fingerprint] names.
bool isViewed(Map<String, String> marks, String path, String fingerprint) =>
    marks[path] == fingerprint;

/// Files marked viewed in one review: path → the fingerprint of the diff that
/// was on screen when the mark was made.
class ReviewViewed extends StateNotifier<Map<String, String>> {
  ReviewViewed() : super(const {});

  /// Flips [path]. A mark left from older content counts as unmarked, so
  /// toggling it marks the current content rather than clearing.
  void toggle(String path, String fingerprint) {
    final next = {...state};
    if (isViewed(state, path, fingerprint)) {
      next.remove(path);
    } else {
      next[path] = fingerprint;
    }
    state = next;
  }

  /// Marks or clears every file in [fingerprints] at once.
  void setAll(Map<String, String> fingerprints, {required bool viewed}) {
    final next = {...state};
    if (viewed) {
      next.addAll(fingerprints);
    } else {
      fingerprints.keys.forEach(next.remove);
    }
    state = next;
  }
}

/// Viewed marks per review, kept for the session: closing a review and opening
/// the same one again picks up where the reader left off.
final reviewViewedProvider =
    StateNotifierProvider.family<
      ReviewViewed,
      Map<String, String>,
      ReviewTarget
    >((ref, _) => ReviewViewed());

/// What a review's pull request button would look up: the forge, and the
/// branch names a request would carry. Null when there is nothing to look up
/// — no forge, or a head that is not a branch. Answered from local git alone;
/// the forge itself is asked only when the button is pressed.
typedef ReviewPrQuery = ({ForgeHost host, String head, String? base});

final reviewPrQueryProvider = FutureProvider.family
    .autoDispose<ReviewPrQuery?, ReviewTarget>((ref, target) async {
      final data = await ref.watch(repoDataProvider(target.repoPath).future);
      final locals = [for (final b in data.branches) b.name];
      String? branchOf(String rev) =>
          prBranchFor(rev, localBranches: locals, remotes: data.remotes);
      final head = branchOf(target.head);
      if (head == null) return null;
      final host = await ref.watch(forgeHostProvider(target.repoPath).future);
      if (host == null) return null;
      return (host: host, head: head, base: branchOf(target.base));
    });

/// Asks the forge for the one open request [query] corresponds to, or null
/// when there is no single answer. Forge failures propagate as [ForgeError]
/// for the caller to report.
Future<PullRequest?> lookUpReviewPullRequest(
  Forge forge,
  ReviewPrQuery query,
) async => pickPullRequest(
  await forge.pullRequestsForBranch(query.head, limit: kPullRequestLimit),
  query.base,
);

/// Which request of which repository a review's header reads.
typedef PullRequestKey = ({String repoPath, int number});

/// The request a review was opened from, with its description. Null when the
/// repository is not on a forge; forge failures reach the reader.
///
/// AutoDispose, and never invalidated: it is read once when a review opens,
/// and closing the review is what lets it go.
final pullRequestDetailProvider = FutureProvider.family
    .autoDispose<PullRequestDetail?, PullRequestKey>((ref, key) async {
      final forge = await ref.watch(forgeProvider(key.repoPath).future);
      if (forge == null) return null;
      return forge.pullRequest(key.number);
    });

/// Which commit of which repository a review's CI list reads.
typedef ReviewChecksKey = ({String repoPath, String sha});

/// CI for the commit a request review shows. Keyed by that commit rather than
/// by the request, so a request pushed to since the review opened still lists
/// the jobs that ran on what is on screen.
final pullRequestChecksProvider = FutureProvider.family
    .autoDispose<ChecksSummary?, ReviewChecksKey>((ref, key) async {
      final forge = await ref.watch(forgeProvider(key.repoPath).future);
      if (forge == null) return null;
      return forge.checksForRef(key.sha);
    });

/// Which of a request review's sections are open. Both start open.
typedef ReviewPullRequestSections = ({bool checks, bool description});

/// Which request review a set of open sections belongs to: one fetch of one
/// request, so a refetch starts open again and a diff mode switch does not.
typedef ReviewPullRequestSectionsKey = ({
  String repoPath,
  int number,
  String head,
});

/// Open sections per request review, kept for the session. Held here rather
/// than in the panel because switching the diff mode replaces the whole
/// review body while it reloads, and the panel with it.
final reviewPullRequestSectionsProvider =
    StateProvider.family<
      ReviewPullRequestSections,
      ReviewPullRequestSectionsKey
    >((ref, _) => (checks: true, description: true));
