import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/forge/forge_error.dart';
import '../../domain/forge/forge_host.dart';
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
  /// Which forge's dialect this transport speaks. Required, with no default:
  /// a default would let a new call site send one forge's headers and token
  /// scheme to the other, and the only reliable reviewer of that is the
  /// compiler.
  final ForgeKind kind;
  final http.Client _client;
  final ForgeToken? _token;
  final Duration _timeout;

  ForgeHttp({
    required this.kind,
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

  /// The headers every request to [kind] carries, with [token] applied under
  /// whichever scheme that forge accepts.
  ///
  /// GitLab reads a personal access token from `PRIVATE-TOKEN`; GitHub reads
  /// it from an `Authorization: Bearer` header. Sending both would hand the
  /// token to a forge that was never asked for it.
  Map<String, String> _headers(ForgeToken? token) => switch (kind) {
    ForgeKind.github => {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      if (token != null) 'Authorization': 'Bearer ${token.value}',
    },
    ForgeKind.gitlab => {
      'Accept': 'application/json',
      if (token != null) 'PRIVATE-TOKEN': token.value,
    },
  };

  Future<ForgeHttpResponse> get(Uri url, {String? ifNoneMatch}) async {
    if (url.scheme != 'https') {
      // Refuse before this ever reaches the network: a forge is always
      // reached over https, no matter what a caller's URL says.
      throw const ForgeMalformed('refusing non-https url');
    }

    final token = _token;
    // A client that follows redirects resends these headers, bearer token
    // included, to wherever the redirect points — a host this call never
    // chose to trust. Building the request by hand and disabling redirects
    // keeps the token from ever going out over a hop this code did not
    // approve; a 3xx response is handled explicitly below instead.
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll({..._headers(token), 'If-None-Match': ?ifNoneMatch});

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      // The detail is fixed text: it is echoed verbatim by toString(), so
      // nothing derived from the request may appear in it.
      throw const ForgeOffline('timed out');
    } on Object {
      // Deliberately broad: this is a GUI application, and narrowing to
      // `on Exception` would let a stray `StateError` or similar escape a
      // network call as an unhandled crash instead of surfacing as
      // "offline", which is the honest answer either way.
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
    if (status >= 300 && status < 400) {
      // GitHub answers 301 when a repository has been renamed. Refusing to
      // follow it means that case surfaces as an error here rather than
      // silently sending the token onward — resolving the new location is
      // a job for the layer that knows what a repository is, not this one.
      throw const ForgeMalformed('unexpected redirect');
    }
    throw forgeErrorForStatus(status, response.headers);
  }

  void close() => _client.close();
}
