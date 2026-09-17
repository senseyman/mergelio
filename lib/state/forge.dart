import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;

import '../data/forge/etag_cache.dart';
import '../data/forge/forge_credentials.dart';
import '../data/forge/forge_http.dart';
import '../data/forge/github_forge.dart';
import '../domain/forge/forge.dart';
import '../domain/forge/forge_host.dart';
import '../domain/forge/models.dart';
import '../domain/git/git_providers.dart';
import 'repo_actions.dart';

part 'forge.freezed.dart';

/// What one repository's pull request section shows.
///
/// Checks are keyed by head sha rather than carried on the request itself, so
/// a request whose CI could not be read is still listed — an absent entry
/// means "nothing to show", which is different from a check that failed.
@freezed
abstract class ForgePanel with _$ForgePanel {
  const factory ForgePanel({
    @Default(<PullRequest>[]) List<PullRequest> pullRequests,
    @Default(<String, ChecksSummary>{}) Map<String, ChecksSummary> checksBySha,
    ForgeRateLimit? rateLimit,
  }) = _ForgePanel;
}

/// The `origin` fetch URL, or empty when there is none.
///
/// Split out from [forgeHostProvider] only so tests can supply a remote
/// without standing up a git repository on disk.
final originRemoteUrlProvider = FutureProvider.family<String, String>((
  ref,
  path,
) async {
  try {
    return await ref.read(repoActionsProvider(path)).remoteUrl('origin');
  } on Object {
    // A repository that cannot answer about its remotes is not on a forge as
    // far as this panel is concerned.
    return '';
  }
});

/// Forge coordinates for the repository at [path], or null when it is not on a
/// forge this version supports. Null is an ordinary answer: the section simply
/// does not appear.
final forgeHostProvider = FutureProvider.family<ForgeHost?, String>((
  ref,
  path,
) async {
  final url = await ref.watch(originRemoteUrlProvider(path).future);
  if (url.isEmpty) return null;
  return resolveForgeHost(url);
});

/// The token git's credential helper holds for this repository's forge.
///
/// Keyed by repository path rather than host because the helper that answers
/// depends on the repository's own configuration.
final forgeTokenProvider = FutureProvider.family<ForgeToken?, String>((
  ref,
  path,
) async {
  final host = await ref.watch(forgeHostProvider(path).future);
  if (host == null) return null;
  final git = ref.watch(gitServiceProvider);
  return ForgeCredentials(git, repoPath: path).fill(host.host);
});

/// One cache for the application session.
///
/// Bodies are held against the validator that proves them current, so this
/// must be discarded when the token changes: a body fetched under one token
/// must never be served under another.
final etagCacheProvider = Provider<EtagCache>((ref) => EtagCache());

/// The http client forge calls go through. Null means the real one.
///
/// Exists so a test can watch what actually goes out on the wire — the
/// token is deliberately unreadable once it is inside the transport, so
/// the only honest way to prove it was passed is to observe the request
/// it produces.
final forgeHttpClientProvider = Provider<http.Client?>((ref) => null);

/// A forge for the repository at [path], or null when it is not on one.
final githubForgeProvider = FutureProvider.family<Forge?, String>((
  ref,
  path,
) async {
  final host = await ref.watch(forgeHostProvider(path).future);
  if (host == null) return null;
  final token = await ref.watch(forgeTokenProvider(path).future);
  return GitHubForge(
    host: host,
    http: ForgeHttp(token: token, client: ref.watch(forgeHttpClientProvider)),
    cache: ref.watch(etagCacheProvider),
  );
});
