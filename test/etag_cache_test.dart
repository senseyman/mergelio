import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/etag_cache.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/domain/forge/forge_error.dart';

final _url = Uri.parse('https://api.github.com/repos/o/r/pulls');

void main() {
  group('EtagCache', () {
    test('stores and returns a body and its validator', () {
      final cache = EtagCache()..store(_url, 'W/"a"', '[1]');
      expect(cache.etagFor(_url), 'W/"a"');
      expect(cache.bodyFor(_url), '[1]');
    });

    test('keys entries by url', () {
      final other = Uri.parse('https://api.github.com/repos/o/r/issues');
      final cache = EtagCache()..store(_url, 'W/"a"', '[1]');
      expect(cache.etagFor(other), isNull);
      expect(cache.bodyFor(other), isNull);
    });

    test('keys entries by the whole url, query string included', () {
      // Paging asks the same path over and over and varies only ?page=N. A
      // key built from the path alone would serve page one forever.
      final page1 = Uri.parse('$_url?page=1');
      final page2 = Uri.parse('$_url?page=2');
      final cache = EtagCache()
        ..store(page1, 'W/"a"', '[1]')
        ..store(page2, 'W/"b"', '[2]');
      expect(cache.bodyFor(page1), '[1]');
      expect(cache.bodyFor(page2), '[2]');
      expect(cache.etagFor(page1), 'W/"a"');
      expect(cache.length, 2);
    });

    test('a response without a validator is not cached', () {
      // With no etag there is nothing to revalidate against, so storing the
      // body would risk serving it forever.
      final cache = EtagCache()..store(_url, null, '[1]');
      expect(cache.bodyFor(_url), isNull);
      expect(cache.length, 0);
    });

    test('an empty validator is treated as no validator', () {
      // An empty If-None-Match would be sent as a header with no value, which
      // no forge will match, so the body could only ever be served stale.
      final cache = EtagCache()..store(_url, '', '[1]');
      expect(cache.bodyFor(_url), isNull);
      expect(cache.length, 0);
    });

    test('a later store replaces an earlier one', () {
      final cache = EtagCache()
        ..store(_url, 'W/"a"', '[1]')
        ..store(_url, 'W/"b"', '[2]');
      expect(cache.etagFor(_url), 'W/"b"');
      expect(cache.bodyFor(_url), '[2]');
      expect(cache.length, 1);
    });

    test('evicts the least recently touched entry once the cap is reached', () {
      // A head sha changes on every push, so an untouched cache grows for as
      // long as the session runs. A small cap here stands in for the real
      // one so the test does not have to insert hundreds of entries to prove
      // the bound holds.
      final cache = EtagCache(maxEntries: 2);
      final a = Uri.parse('$_url/a');
      final b = Uri.parse('$_url/b');
      final c = Uri.parse('$_url/c');

      cache.store(a, 'W/"a"', '[a]');
      cache.store(b, 'W/"b"', '[b]');
      cache.store(c, 'W/"c"', '[c]');

      expect(cache.length, 2);
      expect(cache.bodyFor(a), isNull, reason: 'oldest entry must be gone');
      expect(cache.bodyFor(b), '[b]');
      expect(cache.bodyFor(c), '[c]');
    });

    test('reading an entry counts as use, so it is not the next eviction', () {
      final cache = EtagCache(maxEntries: 2);
      final a = Uri.parse('$_url/a');
      final b = Uri.parse('$_url/b');
      final c = Uri.parse('$_url/c');

      cache.store(a, 'W/"a"', '[a]');
      cache.store(b, 'W/"b"', '[b]');
      // Touching a moves it to the front of the recency order, ahead of b —
      // without this, a plain insertion-order cap would evict a here too.
      cache.bodyFor(a);
      cache.store(c, 'W/"c"', '[c]');

      expect(cache.length, 2);
      expect(cache.bodyFor(a), '[a]', reason: 'freshly read, must survive');
      expect(cache.bodyFor(b), isNull, reason: 'least recently used, evicted');
      expect(cache.bodyFor(c), '[c]');
    });

    test(
      'overwriting an existing entry does not shrink the cache below cap',
      () {
        final cache = EtagCache(maxEntries: 2);
        final a = Uri.parse('$_url/a');
        final b = Uri.parse('$_url/b');

        cache.store(a, 'W/"a"', '[a]');
        cache.store(b, 'W/"b"', '[b]');
        cache.store(a, 'W/"a2"', '[a2]');

        expect(cache.length, 2);
        expect(cache.bodyFor(a), '[a2]');
        expect(cache.bodyFor(b), '[b]');
      },
    );

    test('clearing drops every entry', () {
      // Signing out must not leave bodies fetched under the old token where a
      // later read can still serve them.
      final other = Uri.parse('https://api.github.com/repos/o/r/issues');
      final cache = EtagCache()
        ..store(_url, 'W/"a"', '[1]')
        ..store(other, 'W/"b"', '[2]')
        ..clear();
      expect(cache.length, 0);
      expect(cache.bodyFor(_url), isNull);
      expect(cache.etagFor(other), isNull);
    });
  });

  group('fetchWithCache', () {
    test('sends no validator on a cold cache and stores the answer', () async {
      var sentIfNoneMatch = 'unset';
      final forge = ForgeHttp(
        client: MockClient((req) async {
          sentIfNoneMatch = req.headers['if-none-match'] ?? 'absent';
          return http.Response('[1]', 200, headers: {'etag': 'W/"a"'});
        }),
      );
      final cache = EtagCache();

      final body = await fetchWithCache(forge, cache, _url);

      expect(sentIfNoneMatch, 'absent');
      expect(body, '[1]');
      expect(cache.bodyFor(_url), '[1]');
    });

    test('revalidates with the stored validator and serves a 304', () async {
      var sentIfNoneMatch = 'unset';
      final forge = ForgeHttp(
        client: MockClient((req) async {
          sentIfNoneMatch = req.headers['if-none-match'] ?? 'absent';
          return http.Response('', 304);
        }),
      );
      final cache = EtagCache()..store(_url, 'W/"a"', '[1]');

      final body = await fetchWithCache(forge, cache, _url);

      expect(sentIfNoneMatch, 'W/"a"');
      expect(body, '[1]', reason: 'a 304 must be served from the cache');
    });

    test('a 304 with nothing cached is a protocol fault, not an empty body', () async {
      // Only a stored validator can produce a 304, so this means the cache was
      // dropped underneath the request; returning '' would look like no data.
      final forge = ForgeHttp(
        client: MockClient((_) async => http.Response('', 304)),
      );

      await expectLater(
        fetchWithCache(forge, EtagCache(), _url),
        throwsA(isA<ForgeMalformed>()),
      );
    });

    test('a fresh 200 replaces the cached body', () async {
      final forge = ForgeHttp(
        client: MockClient(
          (_) async => http.Response('[2]', 200, headers: {'etag': 'W/"b"'}),
        ),
      );
      final cache = EtagCache()..store(_url, 'W/"a"', '[1]');

      expect(await fetchWithCache(forge, cache, _url), '[2]');
      expect(cache.etagFor(_url), 'W/"b"');
    });
  });
}
