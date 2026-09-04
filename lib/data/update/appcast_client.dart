import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

import '../../domain/update/update_manifest.dart';
import '../../domain/update/update_public_key.dart';

/// GitHub resolves /releases/latest to the newest published, non-prerelease
/// release, so release candidates never reach anyone who did not ask for one.
const String kProductionAppcastUrl =
    'https://github.com/senseyman/mergelio/releases/latest/download/appcast.json';

// Rehearsal knobs, set with --dart-define. They point a build at a local
// manifest signed by a throwaway key, which is what makes the whole flow
// testable without publishing anything.
const String _appcastUrlOverride = String.fromEnvironment(
  'MERGELIO_APPCAST_URL',
);
const String _publicKeyOverride = String.fromEnvironment(
  'MERGELIO_UPDATE_PUBLIC_KEY',
);

/// Where this build looks for its manifest.
///
/// A release build always uses the production URL. Honouring an override there
/// would mean anyone who can set an environment variable can also choose which
/// binary the app installs, which is the whole thing this design prevents.
String resolveAppcastUrl() => (!kReleaseMode && _appcastUrlOverride.isNotEmpty)
    ? _appcastUrlOverride
    : kProductionAppcastUrl;

/// The key a manifest must be signed with. Overridable on the same terms, so a
/// rehearsal signs with a throwaway key and the real key never leaves storage.
String resolveUpdatePublicKey() =>
    (!kReleaseMode && _publicKeyOverride.isNotEmpty)
    ? _publicKeyOverride
    : kUpdatePublicKeyBase64;

/// Plaintext HTTP is refused outright, except on loopback in a non-release
/// build - that is where a local rehearsal server lives. The signature is the
/// real guard; this just keeps a mistyped URL from becoming a downgrade path.
bool isTransportAllowed(Uri url, {required bool releaseMode}) {
  if (url.isScheme('https')) return true;
  if (releaseMode || !url.isScheme('http')) return false;
  return const {'localhost', '127.0.0.1', '::1'}.contains(url.host);
}

/// The manifest could not be retrieved. Ordinary and not worth alarming anyone
/// over: no network, a proxy in the way, GitHub having a bad day.
class UpdateFetchError implements Exception {
  final String message;
  const UpdateFetchError(this.message);
  @override
  String toString() => 'UpdateFetchError: $message';
}

/// The manifest arrived but is not the one this project signed. Never retried
/// and never shown as an available update - whoever served it is not us.
class UpdateSignatureError implements Exception {
  const UpdateSignatureError();
  @override
  String toString() => 'UpdateSignatureError: manifest signature is not valid';
}

class AppcastClient {
  final http.Client _client;
  final String _publicKeyBase64;
  final Uri _manifestUrl;
  final Uri _signatureUrl;

  AppcastClient({
    http.Client? client,
    String? publicKeyBase64,
    Uri? manifestUrl,
    Uri? signatureUrl,
  }) : _client = client ?? http.Client(),
       _publicKeyBase64 = publicKeyBase64 ?? resolveUpdatePublicKey(),
       _manifestUrl = manifestUrl ?? Uri.parse(resolveAppcastUrl()),
       _signatureUrl = signatureUrl ?? Uri.parse('${resolveAppcastUrl()}.sig');

  Future<UpdateManifest> fetch() async {
    final manifest = await _get(_manifestUrl);
    final signature = await _get(_signatureUrl);

    if (!await _verify(manifest.bodyBytes, signature.body)) {
      throw const UpdateSignatureError();
    }

    // Decode only after the signature holds: the bytes that were verified are
    // the bytes that get parsed, with no re-encoding in between.
    try {
      final json = jsonDecode(utf8.decode(manifest.bodyBytes));
      return UpdateManifest.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      throw UpdateFetchError('manifest is not readable: $e');
    }
  }

  Future<http.Response> _get(Uri url) async {
    if (!isTransportAllowed(url, releaseMode: kReleaseMode)) {
      throw UpdateFetchError('refusing to fetch a manifest over $url');
    }
    final http.Response response;
    try {
      response = await _client.get(
        url,
        headers: const {'User-Agent': 'mergelio-updater'},
      );
    } catch (e) {
      throw UpdateFetchError('$url: $e');
    }
    if (response.statusCode != 200) {
      throw UpdateFetchError('$url: HTTP ${response.statusCode}');
    }
    return response;
  }

  Future<bool> _verify(List<int> message, String signatureBase64) async {
    try {
      final signature = base64Decode(signatureBase64.trim());
      final publicKey = SimplePublicKey(
        base64Decode(_publicKeyBase64.trim()),
        type: KeyPairType.ed25519,
      );
      return await Ed25519().verify(
        message,
        signature: Signature(signature, publicKey: publicKey),
      );
    } catch (_) {
      // Malformed base64, a wrong key length, a truncated signature: all of
      // them mean the same thing here.
      return false;
    }
  }
}
