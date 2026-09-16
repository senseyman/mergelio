import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

/// A [Forge] whose answers and failures a test controls directly.
///
/// Each method can be armed with an error so a single failing call can be
/// exercised without failing the rest, and each call is counted so refresh
/// and caching behaviour can be asserted.
class FakeForge implements Forge {
  @override
  final ForgeHost host;

  final List<PullRequest> pullRequestsResult;
  final List<Issue> issuesResult;
  final ChecksSummary checksResult;

  final ForgeError? pullRequestsError;
  final ForgeError? pullRequestsForBranchError;
  final ForgeError? issuesError;
  final ForgeError? checksError;

  int pullRequestsCalls = 0;
  int pullRequestsForBranchCalls = 0;
  int issuesCalls = 0;
  int checksCalls = 0;

  /// Refs asked about, in order, so a test can prove a commit was queried.
  final List<String> checkedRefs = [];

  FakeForge({
    required this.host,
    List<PullRequest> pullRequests = const [],
    List<Issue> issues = const [],
    ChecksSummary? checks,
    this.pullRequestsError,
    this.pullRequestsForBranchError,
    this.issuesError,
    this.checksError,
  }) : pullRequestsResult = pullRequests,
       issuesResult = issues,
       checksResult =
           checks ?? const ChecksSummary(overall: ChecksOverall.none);

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async {
    pullRequestsCalls++;
    final error = pullRequestsError;
    if (error != null) throw error;
    return pullRequestsResult.take(limit).toList(growable: false);
  }

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async {
    pullRequestsForBranchCalls++;
    final error = pullRequestsForBranchError;
    if (error != null) throw error;
    return pullRequestsResult
        .where((p) => p.sourceBranch == branch)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<ChecksSummary> checksForRef(String ref) async {
    checksCalls++;
    checkedRefs.add(ref);
    final error = checksError;
    if (error != null) throw error;
    return checksResult;
  }

  @override
  Future<List<Issue>> issues({int limit = 50}) async {
    issuesCalls++;
    final error = issuesError;
    if (error != null) throw error;
    return issuesResult.take(limit).toList(growable: false);
  }
}
