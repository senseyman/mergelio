// Where a forge lives: github.com and gitlab.com, or an installation of
// either on a host of its own. Pure string work, like forge_host.dart: every
// URL a forge call or a browser link goes to is built here, from a host the
// person typed or the clouds' fixed names — never from a forge response.

import 'forge_host.dart';

/// One forge installation: which product it runs and where.
class ForgeServer {
  final ForgeKind kind;

  /// Lower-case host name, without scheme or port.
  final String host;

  /// The https port, or null for the default one.
  final int? port;

  const ForgeServer({required this.kind, required this.host, this.port});

  /// Whether this is github.com or gitlab.com rather than a self-hosted
  /// installation.
  bool get isCloud =>
      port == null &&
      ((kind == ForgeKind.github && host == _githubHost) ||
          (kind == ForgeKind.gitlab && host == _gitlabHost));

  /// Host and port as a URL authority and as `git credential` spells a host.
  /// A token for an installation on a non-default port is a different
  /// credential from one on the default port, so the port is part of it.
  String get credentialHost => port == null ? host : '$host:$port';

  /// What settings store this server under. The same text as
  /// [credentialHost], so the two can never name different servers.
  String get key => credentialHost;

  /// Where the REST API lives. github.com alone serves it from a host of its
  /// own; GitHub Enterprise Server puts it under `/api/v3` and every GitLab
  /// under `/api/v4`, on the installation's own host.
  String get _apiAuthority =>
      kind == ForgeKind.github && isCloud ? 'api.github.com' : credentialHost;

  String get _apiPrefix => switch (kind) {
    ForgeKind.github => isCloud ? '' : '/api/v3',
    ForgeKind.gitlab => '/api/v4',
  };

  /// The API root as text, for a caller that must splice an already-escaped
  /// segment in and so cannot go through [api].
  String get apiBase => 'https://$_apiAuthority$_apiPrefix';

  /// An API URL for [path], which must start with `/`.
  Uri api(String path, [Map<String, String>? query]) =>
      Uri.https(_apiAuthority, '$_apiPrefix$path', query);

  /// A web page on this installation, for [path] starting with `/`.
  Uri web(String path, [Map<String, String>? query]) =>
      Uri.https(credentialHost, path, query);

  /// The server [key] and [kindName] were stored as, or null when they no
  /// longer describe one — a settings file edited by hand, or written by a
  /// version that knew a forge this one does not.
  static ForgeServer? fromKey(String key, String kindName) {
    final kind = ForgeKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind == null || key.isEmpty) return null;
    final parsed = parseForgeServerUrl(key, kind, allowCloud: true);
    final server = parsed.server;
    // Only an exact round trip counts: a key that parses only after being
    // normalised is not the one this version wrote.
    return server != null && server.key == key ? server : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ForgeServer &&
      other.kind == kind &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(kind, host, port);

  @override
  String toString() => 'ForgeServer($kind, $credentialHost)';
}

const _githubHost = 'github.com';
const _gitlabHost = 'gitlab.com';

/// github.com.
const kGithubCloud = ForgeServer(kind: ForgeKind.github, host: _githubHost);

/// gitlab.com.
const kGitlabCloud = ForgeServer(kind: ForgeKind.gitlab, host: _gitlabHost);

/// Host names that belong to a public cloud, whichever way they are typed.
const _cloudHosts = {
  'github.com',
  'www.github.com',
  'api.github.com',
  'gitlab.com',
  'www.gitlab.com',
};

/// Why a typed server URL was refused.
enum ForgeServerUrlProblem {
  /// Not something that names a host.
  invalid,

  /// `http://`: the token would go over the network unencrypted.
  notHttps,

  /// An installation under a sub-path (`https://corp/gitlab`), which this
  /// version does not address.
  hasPath,

  /// github.com or gitlab.com, which have their own account entries.
  isCloud,
}

/// A parsed server URL, or why it was refused. Exactly one is set.
typedef ForgeServerUrl = ({
  ForgeServer? server,
  ForgeServerUrlProblem? problem,
});

/// Reads what a person typed as the address of a [kind] installation.
///
/// A bare host means https. Anything that would put more than a host and a
/// port into the URLs built from it — credentials, a path, a query — is
/// refused rather than dropped, so what is stored is exactly what was
/// typed, minus case and the default port.
ForgeServerUrl parseForgeServerUrl(
  String input,
  ForgeKind kind, {
  bool allowCloud = false,
}) {
  ForgeServerUrl fail(ForgeServerUrlProblem p) => (server: null, problem: p);
  final raw = input.trim();
  if (raw.isEmpty) return fail(ForgeServerUrlProblem.invalid);
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null) return fail(ForgeServerUrlProblem.invalid);
  if (uri.scheme == 'http') return fail(ForgeServerUrlProblem.notHttps);
  if (uri.scheme != 'https') return fail(ForgeServerUrlProblem.invalid);
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    return fail(ForgeServerUrlProblem.invalid);
  }
  final host = uri.host.toLowerCase();
  // A host goes into a `git credential` body, which is line-structured, and
  // into URLs; anything outside a plain host name has no business in either.
  if (!RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(host) ||
      host.contains('..')) {
    return fail(ForgeServerUrlProblem.invalid);
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    return fail(ForgeServerUrlProblem.hasPath);
  }
  // Uri already drops the default port, so `:443` reads as no port at all.
  final port = uri.hasPort ? uri.port : null;
  // Uri takes any digits; only these name a port something can listen on.
  if (port != null && (port < 1 || port > 65535)) {
    return fail(ForgeServerUrlProblem.invalid);
  }
  if (_cloudHosts.contains(host)) {
    if (!allowCloud || port != null) return fail(ForgeServerUrlProblem.isCloud);
    final cloud = kind == ForgeKind.github ? kGithubCloud : kGitlabCloud;
    return host.endsWith(cloud.host) && !host.startsWith('api.')
        ? (server: cloud, problem: null)
        : fail(ForgeServerUrlProblem.isCloud);
  }
  return (
    server: ForgeServer(kind: kind, host: host, port: port),
    problem: null,
  );
}
