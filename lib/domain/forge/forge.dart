import 'forge_host.dart';
import 'models.dart';

/// Read access to one repository on one forge.
///
/// Implementations answer for a single repository fixed at construction, so
/// no method takes a project argument. Every method either returns data or
/// throws a [ForgeError]; none returns an empty list to mean failure.
///
/// This is the only forge type the UI layers know about. They never see
/// HTTP, JSON, or a status code, which is what lets them be tested against a
/// fake with no network at all.
abstract class Forge {
  /// The repository this instance answers for.
  ForgeHost get host;

  /// Open requests, most recently updated first, capped at [limit].
  Future<List<PullRequest>> pullRequests({int limit = 50});

  /// Open requests whose source branch is [branch]. Usually zero or one, but
  /// a branch can back more than one request across different targets.
  Future<List<PullRequest>> pullRequestsForBranch(String branch);

  /// CI status for [ref], which may be a sha or a branch name. A repository
  /// with no CI configured reports [ChecksOverall.none] rather than throwing.
  Future<ChecksSummary> checksForRef(String ref);

  /// Open issues, most recently updated first, capped at [limit].
  Future<List<Issue>> issues({int limit = 50});
}
