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

  /// Upper bound on pages followed for one list, and a backstop rather than
  /// the usual reason paging ends: a list normally stops as soon as it holds
  /// the rows it was asked for. This bounds the case where it never does —
  /// a repository whose pages are mostly entries this caller discards would
  /// otherwise spend a whole rate limit filling one sidebar section.
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

  /// The largest page GitHub will serve. Asking for more is not an error; it
  /// is silently clamped, which would leave the request describing a page it
  /// never gets.
  static const _maxPerPage = 100;

  Uri _repoUrl(
    String path, [
    Map<String, String> query = const {},
    int perPage = _maxPerPage,
  ]) => Uri.https(_apiHost, '/repos/${host.owner}/${host.repo}$path', {
    'per_page': '${perPage.clamp(1, _maxPerPage)}',
    ...query,
  });

  /// Characters git forbids in a ref, plus the few that would change the shape
  /// of the URL a ref is spliced into.
  static final _unusableInRef = RegExp(r'''[\x00-\x20\x7f~^:?*%#\[\]\\"<>|]''');

  /// Refuses a ref that cannot safely become part of a URL path.
  ///
  /// This rejects rather than rewrites, and returns nothing, so no caller can
  /// mistake it for a sanitiser and use a "cleaned" value that never existed.
  ///
  /// A branch name legitimately contains `/`, and GitHub wants those slashes
  /// literal, so they are kept. A `.` or `..` segment is a different matter:
  /// Uri resolves it away, so an unchecked ref addresses a different
  /// repository under this caller's token. Git forbids both in a real ref, so
  /// refusing them costs nothing that was ever going to work.
  void _rejectUnusableRef(String ref) {
    final segments = ref.split('/');
    if (ref.isEmpty ||
        _unusableInRef.hasMatch(ref) ||
        segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      // The detail is fixed text: it is echoed verbatim by toString(), so the
      // ref itself must not appear in it.
      throw const ForgeMalformed('refusing an unusable ref');
    }
  }

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

  /// Reads [url], and the pages it links onward to while it still needs them,
  /// concatenating the decoded lists.
  ///
  /// Paging stops as soon as [usableCount] reports [limit] rows in hand, or
  /// at [maxPages], whichever comes first. The count is of rows a caller can
  /// actually use rather than of raw entries, because an endpoint can answer
  /// with entries that are dropped on the way out — the issues endpoint
  /// includes pull requests — and counting those would end the list short.
  ///
  /// This repeats fetchWithCache rather than calling it because paging needs
  /// the response headers to find the next link, and fetchWithCache returns
  /// only a body. Collapsing the two would mean leaking headers out of it for
  /// one caller.
  Future<List<Object?>> _readList(
    Uri url, {
    required int limit,
    required int Function(List<Object?>) usableCount,
  }) async {
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
      if (usableCount(items) >= limit) break;
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
      }, limit),
      limit: limit,
      usableCount: (items) => parsePullRequests(items).length,
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
      }, limit),
      limit: limit,
      usableCount: (items) => parsePullRequests(items).length,
    );
    return parsePullRequests(items).take(limit).toList(growable: false);
  }

  @override
  Future<ChecksSummary> checksForRef(String ref) async {
    // Either endpoint may be absent for a repository, or invisible to this
    // token. Neither case is a failure of the other, and a repository with no
    // CI at all simply has nothing to report.
    _rejectUnusableRef(ref);
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
    final List<Object?> items;
    try {
      items = await _readList(
        _repoUrl('/issues', {
          'state': 'open',
          'sort': 'updated',
          'direction': 'desc',
        }, limit),
        limit: limit,
        usableCount: (items) => parseIssues(items).length,
      );
    } on ForgeServerFault catch (e) {
      // A repository can switch its issue tracker off, and forks and mirrors
      // often have. GitHub answers 410 Gone for the endpoint then. Nothing is
      // broken, so reporting a server fault would blame the forge for a
      // deliberate setting — there is simply no tracker, and nothing open.
      // Narrow on purpose: every other fault still reaches the caller.
      if (e.status != 410) rethrow;
      return const [];
    }
    return parseIssues(items).take(limit).toList(growable: false);
  }
}
