import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/update/appcast_client.dart';

final _manifest = File('test/fixtures/update/appcast.json').readAsBytesSync();
final _signature = File(
  'test/fixtures/update/appcast.json.sig',
).readAsStringSync();
final _publicKey = File(
  'test/fixtures/update/test_public_key.txt',
).readAsStringSync().trim();

AppcastClient _client({
  List<int>? manifest,
  String? signature,
  int status = 200,
  String publicKey = '',
}) {
  final mock = MockClient((req) async {
    if (status != 200) return http.Response('nope', status);
    return req.url.path.endsWith('.sig')
        ? http.Response(signature ?? _signature, 200)
        : http.Response.bytes(manifest ?? _manifest, 200);
  });
  return AppcastClient(
    client: mock,
    publicKeyBase64: publicKey.isEmpty ? _publicKey : publicKey,
    manifestUrl: Uri.parse('https://example.invalid/appcast.json'),
    signatureUrl: Uri.parse('https://example.invalid/appcast.json.sig'),
  );
}

void main() {
  test('accepts a correctly signed manifest', () async {
    final m = await _client().fetch();
    expect(m.version, '9.9.9');
    expect(m.artifacts, isNotEmpty);
  });

  test('rejects a manifest whose bytes were altered', () async {
    final tampered = [..._manifest];
    tampered[tampered.length - 2] = tampered[tampered.length - 2] ^ 0x01;
    expect(
      () => _client(manifest: tampered).fetch(),
      throwsA(isA<UpdateSignatureError>()),
    );
  });

  test('rejects a manifest signed by a different key', () async {
    // A valid Ed25519 public key that did not sign this manifest.
    const otherKey = 'ILUnpBLJb5rvo1FUkDBjkvJlvJDPjT2xJH1z1QDUv0k=';
    expect(
      () => _client(publicKey: otherKey).fetch(),
      throwsA(isA<UpdateSignatureError>()),
    );
  });

  test('rejects a malformed signature without crashing', () async {
    expect(
      () => _client(signature: 'not base64 at all!!').fetch(),
      throwsA(isA<UpdateSignatureError>()),
    );
  });

  test('reports a failed fetch', () async {
    expect(
      () => _client(status: 404).fetch(),
      throwsA(isA<UpdateFetchError>()),
    );
  });

  test('always allows https', () {
    final url = Uri.parse('https://github.com/x/appcast.json');
    expect(isTransportAllowed(url, releaseMode: true), isTrue);
    expect(isTransportAllowed(url, releaseMode: false), isTrue);
  });

  test('never allows plaintext to a public host', () {
    final url = Uri.parse('http://example.invalid/appcast.json');
    expect(isTransportAllowed(url, releaseMode: false), isFalse);
    expect(isTransportAllowed(url, releaseMode: true), isFalse);
  });

  test('allows a loopback rehearsal server only outside a release build', () {
    final url = Uri.parse('http://localhost:8000/appcast.json');
    expect(isTransportAllowed(url, releaseMode: false), isTrue);
    expect(isTransportAllowed(url, releaseMode: true), isFalse);
  });
}
