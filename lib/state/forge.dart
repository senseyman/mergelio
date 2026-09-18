import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;

import '../data/forge/etag_cache.dart';
import '../data/forge/forge_credentials.dart';
import '../data/forge/forge_http.dart';
import '../data/forge/github_forge.dart';
import '../data/forge/github_parse.dart';
import '../domain/forge/forge.dart';
import '../domain/forge/forge_error.dart';
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
  // Named, because the host very likely holds the user's own push credential
  // too, and an unnamed lookup returns whichever the helper reaches first.
  return ForgeCredentials(
    git,
    repoPath: path,
  ).fill(host.host, forgeTokenUsername);
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

/// How many pull requests one repository contributes to the section.
///
/// Ten keeps an unauthenticated session usable across a couple of
/// repositories an hour; twenty does not. See [kForgeRequestsPerOpen] for
/// what each row costs.
const kPullRequestLimit = 10;

/// What opening one repository's section spends against the hourly budget:
/// a single request for the list, then two for every row — CI status lives
/// behind two endpoints, combined status and check runs, and a row's badge
/// needs both.
///
/// This is the number the preferences copy quotes, so it is defined here
/// next to the limit it depends on rather than written out in prose twice.
const kForgeRequestsPerOpen = 1 + 2 * kPullRequestLimit;

/// How many CI reads may be in flight at once.
const kChecksConcurrency = 4;

/// Runs [fetch] for every key, never more than [limit] at a time, and keeps
/// whichever results come back non-null.
///
/// The cap exists because a repository's pull requests can outnumber what
/// the hourly budget can afford to check all at once; a fixed number of
/// workers pulls from a shared queue instead of firing every request at
/// once.
Future<Map<K, V>> fetchWithLimit<K, V>(
  Iterable<K> keys,
  int limit,
  Future<V?> Function(K) fetch,
) async {
  final pending = keys.toList(growable: false);
  final out = <K, V>{};
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= pending.length) return;
      final key = pending[index];
      final value = await fetch(key);
      if (value != null) out[key] = value;
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < limit && i < pending.length; i++) worker(),
  ];
  await Future.wait(workers);
  return out;
}

/// Everything the pull request section shows for the repository at [path].
///
/// Deliberately not autoDispose: invalidating an autoDispose family provider
/// re-runs it even when nobody is listening, which against an hourly budget
/// turns a refresh into a fetch storm. Refresh by invalidating from the
/// widget that reads it.
final pullRequestPanelProvider = FutureProvider.family<ForgePanel, String>((
  ref,
  path,
) async {
  final forge = await ref.watch(githubForgeProvider(path).future);
  if (forge == null) return const ForgePanel();

  final prs = await forge.pullRequests(limit: kPullRequestLimit);

  final checks = await fetchWithLimit<String, ChecksSummary>(
    prs.map((p) => p.headSha),
    kChecksConcurrency,
    (sha) async {
      try {
        return await forge.checksForRef(sha);
      } on ForgeError {
        // CI that cannot be read costs the row its badge, not its place in
        // the list. The request itself was read successfully.
        return null;
      }
    },
  );

  return ForgePanel(pullRequests: prs, checksBySha: checks);
});

/// What is left of the forge's hourly budget, or null when it cannot be
/// read.
///
/// Read from the forge's own budget endpoint rather than from response
/// headers, so the transport keeps returning models and nothing else. The
/// http client is the same overridable seam [githubForgeProvider] uses, so
/// a test can answer this call without reaching the network.
final forgeRateLimitProvider = FutureProvider.family<ForgeRateLimit?, String>((
  ref,
  path,
) async {
  final host = await ref.watch(forgeHostProvider(path).future);
  if (host == null) return null;
  final token = await ref.watch(forgeTokenProvider(path).future);
  try {
    final response = await ForgeHttp(
      token: token,
      client: ref.watch(forgeHttpClientProvider),
    ).get(Uri.https('api.github.com', '/rate_limit'));
    return parseRateLimit(jsonDecode(response.body));
  } on Object {
    // The budget is a courtesy. Failing to read it must never fail the
    // panel.
    return null;
  }
});
