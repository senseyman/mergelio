import 'dart:convert';

import '../../domain/forge/forge.dart';
import '../../domain/forge/forge_error.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/models.dart';
import 'etag_cache.dart';
import 'forge_http.dart';
import 'gitlab_parse.dart';
import 'link_header.dart';

/// Read access to one project on gitlab.com.
class GitlabForge implements Forge {
  @override
  final ForgeHost host;

  final ForgeHttp _http;
  final EtagCache _cache;

  /// Upper bound on pages followed for one list — a backstop, not the usual
  /// reason paging ends. Without it a project with thousands of open requests
  /// could spend a whole session's budget filling one sidebar section.
  final int maxPages;

  GitlabForge({
    required this.host,
    required ForgeHttp http,
    EtagCache? cache,
    this.maxPages = 5,
  }) : // The public parameter is named for callers; the field stays
       // private, so this cannot become an initializing formal.
       // ignore: prefer_initializing_formals
       _http = http,
       _cache = cache ?? EtagCache();

  /// The largest page GitLab serves; asking for more is silently clamped.
  static const _maxPerPage = 100;

  /// One API url for this project.
  ///
  /// GitLab addresses a project by its full path as a single escaped path
  /// segment (`group%2Fsub%2Fapp`). Neither `Uri.https` nor `pathSegments`
  /// can express that: the first escapes the percent sign again, the second
  /// turns the escaped slashes back into separators. Building the string and
  /// parsing it is what leaves exactly one level of escaping on the wire.
  Uri _projectUrl(
    String path, [
    Map<String, String> query = const {},
    int perPage = _maxPerPage,
  ]) =>
      Uri.parse(
        'https://${host.host}/api/v4/projects'
        '/${Uri.encodeComponent(host.projectPath)}$path',
      ).replace(
        queryParameters: {
          'per_page': '${perPage.clamp(1, _maxPerPage)}',
          ...query,
        },
      );

  /// Characters git forbids in a ref, plus a few that would change the shape
  /// of the url the ref is spliced into.
  static final _unusableInRef = RegExp(r'''[\x00-\x20\x7f~^:?*%#\[\]\\"<>|]''');

  /// Refuses a ref that cannot safely become part of a url.
  ///
  /// It rejects rather than rewrites: a caller must never be able to mistake
  /// this for a sanitiser and use a "cleaned" value that never existed.
  /// Escaping already makes a `..` inert here, but a ref carrying one is
  /// broken in a way worth refusing rather than asking the forge about.
  void _rejectUnusableRef(String ref) {
    final segments = ref.split('/');
    if (ref.isEmpty ||
        _unusableInRef.hasMatch(ref) ||
        segments.any((s) => s.isEmpty || s == '.' || s == '..')) {
      // The detail is fixed text: it is echoed verbatim by toString(), so the
      // ref itself must not appear in it.
      throw const ForgeMalformed('refusing unusable ref');
    }
  }

  Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      // Fixed text: the detail is echoed verbatim, so no part of the body
      // may appear in it.
      throw const ForgeMalformed('response was not json');
    }
  }

  /// Reads pages until [limit] usable rows are in hand or [maxPages] is
  /// reached, concatenating the decoded lists.
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
          throw const ForgeMalformed('cache miss on revalidated response');
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

  Uri _mergeRequestsUrl(Map<String, String> query, int limit) => _projectUrl(
    '/merge_requests',
    {'state': 'opened', 'order_by': 'updated_at', 'sort': 'desc', ...query},
    limit,
  );

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async {
    final items = await _readList(
      _mergeRequestsUrl(const {}, limit),
      limit: limit,
      usableCount: (items) => parseMergeRequests(items).length,
    );
    return parseMergeRequests(items).take(limit).toList(growable: false);
  }

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async {
    final items = await _readList(
      _mergeRequestsUrl({'source_branch': branch}, limit),
      limit: limit,
      usableCount: (items) => parseMergeRequests(items).length,
    );
    return parseMergeRequests(items).take(limit).toList(growable: false);
  }

  @override
  Future<ChecksSummary> checksForRef(String ref) async {
    _rejectUnusableRef(ref);
    // A branch name carries slashes that belong to the ref, not to the url,
    // so the ref is one escaped segment for the same reason the project path
    // is.
    final json = await _optionalJson(
      _projectUrl('/repository/commits/${Uri.encodeComponent(ref)}/statuses'),
    );
    return parseCommitStatuses(json);
  }

  /// Reads one url, treating "not visible" as "not configured".
  ///
  /// A commit the token cannot see and a project with no CI are the same
  /// thing to a row: nothing to report, which is not a failure.
  Future<Object?> _optionalJson(Uri url) async {
    try {
      final body = await fetchWithCache(_http, _cache, url);
      return _decode(body);
    } on ForgeNotVisible {
      return null;
    }
  }

  @override
  Future<String?> defaultBranch() async {
    final json = await _optionalJson(_projectUrl(''));
    if (json is! Map) return null;
    final branch = json['default_branch'];
    return branch is String && branch.isNotEmpty ? branch : null;
  }

  @override
  Future<List<Issue>> issues({int limit = 50}) async {
    final List<Object?> items;
    try {
      items = await _readList(
        _projectUrl('/issues', {
          'state': 'opened',
          'order_by': 'updated_at',
          'sort': 'desc',
        }, limit),
        limit: limit,
        usableCount: (items) => parseGitlabIssues(items).length,
      );
    } on ForgeNotVisible {
      // A project can switch its issue tracker off, and GitLab answers 403 or
      // 404 for the endpoint then — both reach here as ForgeNotVisible.
      // Nothing is broken: there is no tracker, so nothing is open. Narrow on
      // purpose, since every other failure still reaches the caller.
      return const [];
    }
    return parseGitlabIssues(items).take(limit).toList(growable: false);
  }
}
