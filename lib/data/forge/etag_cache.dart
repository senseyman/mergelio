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
///
/// Bounded, not merely per-session: a head sha changes on every push, so a
/// long-running session that keeps opening and pushing to repositories would
/// otherwise grow this without limit. [maxEntries] caps it, evicting the
/// least recently touched entry — read or write — once a store would put it
/// over the limit.
class EtagCache {
  /// A `LinkedHashMap` (the default for a `Map` literal) iterates in
  /// insertion order and re-inserting an existing key moves it to the end
  /// without changing that key's identity elsewhere — exactly what an LRU
  /// order needs: touching an entry only has to remove and re-add it to
  /// become the most recently used.
  final _entries = <Uri, _Entry>{};

  final int maxEntries;

  EtagCache({this.maxEntries = 300}) : assert(maxEntries > 0);

  String? etagFor(Uri url) => _touch(url)?.etag;

  String? bodyFor(Uri url) => _touch(url)?.body;

  /// Reads [url]'s entry, if any, moving it to the most-recently-used end so
  /// a read counts as use exactly like a write does.
  _Entry? _touch(Uri url) {
    final entry = _entries.remove(url);
    if (entry == null) return null;
    _entries[url] = entry;
    return entry;
  }

  /// Records [body] against [etag]. A response with no validator is dropped:
  /// there would be no way to revalidate it, so it could only be served stale.
  void store(Uri url, String? etag, String body) {
    if (etag == null || etag.isEmpty) return;
    // Removing before inserting means a store of a key already present moves
    // it to the most-recently-used end rather than keeping its old position
    // — an overwrite is a use too, and must not make its own key look like
    // the next thing due for eviction.
    _entries.remove(url);
    _entries[url] = _Entry(etag, body);
    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
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
