import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/update/update_downloader.dart';
import 'package:mergelio/domain/update/update_manifest.dart';

const _body = 'pretend this is an installer';
final _hash = sha256.convert(utf8.encode(_body)).toString();

UpdateDownloader _downloader(String body) => UpdateDownloader(
  client: MockClient.streaming((req, bodyStream) async {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
    );
  }),
);

UpdateArtifact _artifact({String? sha}) => UpdateArtifact(
  url: 'https://example.invalid/Mergelio-9.9.9-macos-arm64-update.zip',
  sha256: sha ?? _hash,
  size: utf8.encode(_body).length,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mergelio-dl-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes a file whose hash matches the manifest', () async {
    final file = await _downloader(_body).download(_artifact(), into: dir);
    expect(file.readAsStringSync(), _body);
    expect(file.path, endsWith('.zip'));
  });

  test('reports progress that ends at the full size', () async {
    final seen = <int>[];
    await _downloader(_body).download(
      _artifact(),
      into: dir,
      onProgress: (received, total) => seen.add(received),
    );
    expect(seen.last, utf8.encode(_body).length);
  });

  test('rejects a payload that does not match the hash', () async {
    await expectLater(
      _downloader('something else entirely').download(_artifact(), into: dir),
      throwsA(isA<UpdateChecksumError>()),
    );
  });

  test('leaves nothing behind when the hash does not match', () async {
    try {
      await _downloader(
        'something else entirely',
      ).download(_artifact(), into: dir);
    } on UpdateChecksumError {
      // expected
    }
    expect(dir.listSync(), isEmpty);
  });
}
