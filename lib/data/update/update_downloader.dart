import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../domain/update/update_manifest.dart';

/// The download does not hash to what the signed manifest promised. The file is
/// deleted before this is thrown: nothing that failed verification is ever left
/// somewhere it could be run by accident.
class UpdateChecksumError implements Exception {
  final String expected;
  final String actual;
  const UpdateChecksumError(this.expected, this.actual);
  @override
  String toString() => 'UpdateChecksumError: expected $expected, got $actual';
}

class UpdateDownloader {
  final http.Client _client;
  UpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  /// Streams [artifact] into [into] and verifies it. The hash is computed while
  /// the bytes arrive, so a large installer is never held in memory twice.
  Future<File> download(
    UpdateArtifact artifact, {
    required Directory into,
    void Function(int received, int total)? onProgress,
  }) async {
    final name = Uri.parse(artifact.url).pathSegments.last;
    final file = File('${into.path}${Platform.pathSeparator}$name');

    final request = http.Request('GET', Uri.parse(artifact.url))
      ..headers['User-Agent'] = 'mergelio-updater';
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: request.url);
    }

    final total = response.contentLength ?? artifact.size;
    var received = 0;
    final digest = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(digest);
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        hasher.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    hasher.close();

    final actual = digest.events.single.toString();
    if (actual != artifact.sha256.toLowerCase()) {
      await file.delete();
      throw UpdateChecksumError(artifact.sha256, actual);
    }
    return file;
  }
}
