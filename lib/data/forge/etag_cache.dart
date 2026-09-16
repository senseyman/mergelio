import '../../domain/forge/forge_error.dart';
import 'forge_http.dart';

/// One cached answer and the validator that proves it is still current.
class _Entry {
  final String etag;
  final String body;
  const _Entry(this.etag, this.body);
}

/// Bodies kept against their validators, so an unchanged resource can be
/// re-read without spending API quota on it.
///
/// Deliberately in-memory and per-session. Forge data going stale across a
/// restart is correct: it was fetched under a token that may since have been
/// revoked, and persisting it would outlive the permission that produced it.
class EtagCache {
  final _entries = <Uri, _Entry>{};

  String? etagFor(Uri url) => _entries[url]?.etag;

  String? bodyFor(Uri url) => _entries[url]?.body;

  /// Records [body] against [etag]. A response with no validator is dropped:
  /// there would be no way to revalidate it, so it could only be served stale.
  void store(Uri url, String? etag, String body) {
    if (etag == null || etag.isEmpty) return;
    _entries[url] = _Entry(etag, body);
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

/// Reads [url], revalidating against [cache] when there is something to
/// revalidate, and returns the body.
Future<String> fetchWithCache(ForgeHttp http, EtagCache cache, Uri url) async {
  final response = await http.get(url, ifNoneMatch: cache.etagFor(url));
  if (response.notModified) {
    final cached = cache.bodyFor(url);
    if (cached == null) {
      // A validator is the only thing that can produce a 304, so an empty
      // cache here means it was dropped mid-flight. Returning the empty body
      // would be indistinguishable from a resource with no content.
      throw const ForgeMalformed('cache miss on a revalidated response');
    }
    return cached;
  }
  cache.store(url, response.etag, response.body);
  return response.body;
}
