import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// A branch review: what [head] brings relative to [base]. [threeDot] reads
/// head against the point it branched from base — what a pull request shows —
/// rather than against base's tip.
class ReviewTarget {
  final String repoPath;
  final String base;
  final String head;
  final bool threeDot;
  const ReviewTarget({
    required this.repoPath,
    required this.base,
    required this.head,
    this.threeDot = true,
  });

  String get baseLabel => compareRefLabel(base);
  String get headLabel => compareRefLabel(head);

  /// The git range this review reads, as the user would type it.
  String get range => reviewRange(baseLabel, headLabel, threeDot: threeDot);

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
  );

  @override
  bool operator ==(Object other) =>
      other is ReviewTarget &&
      other.repoPath == repoPath &&
      other.base == base &&
      other.head == head &&
      other.threeDot == threeDot;

  @override
  int get hashCode => Object.hash(repoPath, base, head, threeDot);
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
  final List<CommitFileChange> files;

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
      final results = await Future.wait<Object>([
        reader.aheadBehind(baseSha, headSha),
        reader.rangeCommits(baseSha, headSha),
        if (fromRev != null) reader.compareFiles(fromRev, headSha),
      ]);
      final page = results[1] as ({List<Commit> commits, bool truncated});
      return ReviewSummary(
        baseSha: baseSha,
        headSha: headSha,
        mergeBase: mergeBase,
        fromRev: fromRev,
        counts: results[0] as AheadBehind,
        commits: page.commits,
        commitsTruncated: page.truncated,
        files: fromRev == null
            ? const []
            : results[2] as List<CommitFileChange>,
      );
    });

/// The two resolved commits a review's diff is read between.
typedef ReviewDiffKey = ({String repoPath, String from, String to});

/// Every file diff of a review, keyed by path, read as one patch. Both sides
/// are object names, so the answer never goes stale and needs no
/// ref-following.
final reviewDiffProvider = FutureProvider.family
    .autoDispose<Map<String, FileDiff>, ReviewDiffKey>((ref, key) async {
      final reader = GitReader(ref.watch(gitServiceProvider), key.repoPath);
      final raw = await reader.rangeDiff(key.from, key.to);
      return {for (final f in parseUnifiedDiff(raw)) f.path: f};
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

/// The open pull request this review corresponds to, with the forge it lives
/// on, or null when there is none to point at — no forge configured, a head
/// that is not a branch, no single matching request, or the forge failing.
/// A review never errors over this; the button just does not appear.
final reviewPullRequestProvider = FutureProvider.family
    .autoDispose<({PullRequest pr, ForgeHost host})?, ReviewTarget>((
      ref,
      target,
    ) async {
      try {
        final data = await ref.read(repoDataProvider(target.repoPath).future);
        final locals = [for (final b in data.branches) b.name];
        String? branchOf(String rev) =>
            prBranchFor(rev, localBranches: locals, remotes: data.remotes);
        final head = branchOf(target.head);
        if (head == null) return null;
        final forge = await ref.watch(forgeProvider(target.repoPath).future);
        if (forge == null) return null;
        final prs = await forge.pullRequestsForBranch(head);
        final pr = pickPullRequest(prs, branchOf(target.base));
        return pr == null ? null : (pr: pr, host: forge.host);
      } catch (_) {
        return null;
      }
    });
