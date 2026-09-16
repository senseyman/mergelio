import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/forge/forge_error.dart';
import 'forge_credentials.dart';

/// One answer from a forge's HTTP API.
class ForgeHttpResponse {
  final int status;
  final String body;
  final Map<String, String> headers;

  const ForgeHttpResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  /// The validator a conditional request needs, if the response carried one.
  String? get etag => headers['etag'];

  /// Whether the body is unchanged since the validator was sent.
  bool get notModified => status == 304;
}

/// Transport for a forge's REST API.
///
/// Owns exactly three concerns: the headers a call needs, the timeout, and
/// turning a failing status into a [ForgeError]. It knows nothing about pull
/// requests, pagination, or caching — that is what keeps it testable: a
/// stub client keeps everything above it testable with no client at all.
class ForgeHttp {
  final http.Client _client;
  final ForgeToken? _token;
  final Duration _timeout;

  ForgeHttp({
    http.Client? client,
    ForgeToken? token,
    Duration timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       // The public parameter is named for callers; the field stays
       // private, so this cannot become an initializing formal.
       // ignore: prefer_initializing_formals
       _token = token,
       // ignore: prefer_initializing_formals
       _timeout = timeout;

  Future<ForgeHttpResponse> get(Uri url, {String? ifNoneMatch}) async {
    if (url.scheme != 'https') {
      // Refuse before this ever reaches the network: a forge is always
      // reached over https, no matter what a caller's URL says.
      throw const ForgeMalformed('refusing non-https url');
    }

    final token = _token;
    final http.Response response;
    try {
      response = await _client
          .get(
            url,
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              if (token != null) 'Authorization': 'Bearer ${token.value}',
              'If-None-Match': ?ifNoneMatch,
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      // The detail is fixed text: it is echoed verbatim by toString(), so
      // nothing derived from the request may appear in it.
      throw const ForgeOffline('timed out');
    } on Object {
      throw const ForgeOffline('could not reach forge');
    }

    final status = response.statusCode;
    if (status == 304 || (status >= 200 && status < 300)) {
      return ForgeHttpResponse(
        status: status,
        body: response.body,
        headers: response.headers,
      );
    }
    throw forgeErrorForStatus(status, response.headers);
  }

  void close() => _client.close();
}
