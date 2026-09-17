import 'dart:convert';

import '../../domain/forge/forge.dart';
import '../../domain/forge/forge_error.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/models.dart';
import 'etag_cache.dart';
import 'forge_http.dart';
import 'github_parse.dart';
import 'link_header.dart';

/// Read access to one repository on github.com.
class GitHubForge implements Forge {
  @override
  final ForgeHost host;

  final ForgeHttp _http;
  final EtagCache _cache;

  /// Upper bound on pages followed for one list. A repository with thousands
  /// of open items would otherwise spend a whole rate limit filling a single
  /// sidebar section.
  final int maxPages;

  GitHubForge({
    required this.host,
    required ForgeHttp http,
    EtagCache? cache,
    this.maxPages = 5,
  }) : // The public parameter is named for callers; the field stays
       // private, so this cannot become an initializing formal.
       // ignore: prefer_initializing_formals
       _http = http,
       _cache = cache ?? EtagCache();

  static const _apiHost = 'api.github.com';
  static const _perPage = 100;

  Uri _repoUrl(String path, [Map<String, String> query = const {}]) =>
      Uri.https(_apiHost, '/repos/${host.owner}/${host.repo}$path', {
        'per_page': '$_perPage',
        ...query,
      });

  /// Decodes one response body, or reports it as unreadable.
  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      // The detail is fixed text: it is echoed verbatim by toString(), so the
      // body itself must not appear in it.
      throw const ForgeMalformed('response was not valid json');
    }
  }

  /// Reads [url] and every page it links onward to, up to [maxPages],
  /// concatenating the decoded lists.
  ///
  /// This repeats fetchWithCache rather than calling it because paging needs
  /// the response headers to find the next link, and fetchWithCache returns
  /// only a body. Collapsing the two would mean leaking headers out of it for
  /// one caller.
  Future<List<Object?>> _readList(Uri url) async {
    final items = <Object?>[];
    Uri? next = url;
    for (var page = 0; page < maxPages && next != null; page++) {
      final response = await _http.get(next, ifNoneMatch: _cache.etagFor(next));
      final String body;
      if (response.notModified) {
        final cached = _cache.bodyFor(next);
        if (cached == null) {
          throw const ForgeMalformed('cache miss on a revalidated response');
        }
        body = cached;
      } else {
        _cache.store(next, response.etag, response.body);
        body = response.body;
      }
      final decoded = _decode(body);
      if (decoded is List) items.addAll(decoded);
      next = nextPageUrl(response.headers['link']);
    }
    return items;
  }

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async {
    final items = await _readList(
      _repoUrl('/pulls', {
        'state': 'open',
        'sort': 'updated',
        'direction': 'desc',
      }),
    );
    return parsePullRequests(items).take(limit).toList(growable: false);
  }

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async {
    final items = await _readList(
      _repoUrl('/pulls', {
        'state': 'open',
        // The head filter is owner-qualified. Without the owner prefix GitHub
        // ignores it and answers with every open request in the repository.
        'head': '${host.owner}:$branch',
      }),
    );
    return parsePullRequests(items).take(limit).toList(growable: false);
  }

  @override
  Future<ChecksSummary> checksForRef(String ref) async {
    // Either endpoint may be absent for a repository, or invisible to this
    // token. Neither case is a failure of the other, and a repository with no
    // CI at all simply has nothing to report.
    final combined = await _optionalObject(_repoUrl('/commits/$ref/status'));
    final checkRuns = await _optionalObject(
      _repoUrl('/commits/$ref/check-runs'),
    );
    return parseChecks(combinedStatus: combined, checkRuns: checkRuns);
  }

  /// Reads one object, treating "not visible" as "not configured".
  Future<Object?> _optionalObject(Uri url) async {
    try {
      final body = await fetchWithCache(_http, _cache, url);
      return _decode(body);
    } on ForgeNotVisible {
      return null;
    }
  }

  @override
  Future<List<Issue>> issues({int limit = 50}) async {
    final items = await _readList(
      _repoUrl('/issues', {
        'state': 'open',
        'sort': 'updated',
        'direction': 'desc',
      }),
    );
    return parseIssues(items).take(limit).toList(growable: false);
  }
}
