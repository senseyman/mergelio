// Turns a git remote URL into the forge coordinates an API call needs. Pure
// string work: the same remote must resolve identically whether it was written
// as https, ssh:// or scp-style, because a repository's remotes often mix them.

import 'forge_server.dart';

/// Which forge product a host runs.
enum ForgeKind { github, gitlab }

/// A repository as a forge addresses it.
class ForgeHost {
  final ForgeKind kind;

  /// Canonical host name, with any `www.` prefix and port removed.
  final String host;

  /// The installation's https port when it is not the default one. Taken
  /// from the registered server, never from the remote: an ssh remote's port
  /// says nothing about where the web and API answer.
  final int? port;

  /// Everything before the repository name. A single account on GitHub; on
  /// GitLab this may be several `/`-separated groups deep.
  final String owner;

  final String repo;

  const ForgeHost({
    required this.kind,
    required this.host,
    required this.owner,
    required this.repo,
    this.port,
  });

  /// The installation this repository lives on.
  ForgeServer get server => ForgeServer(kind: kind, host: host, port: port);

  /// The project as git and the web UI spell it. Callers that need an API path
  /// segment must escape this themselves; it is stored unescaped.
  String get projectPath => '$owner/$repo';

  @override
  bool operator ==(Object other) =>
      other is ForgeHost &&
      other.kind == kind &&
      other.host == host &&
      other.owner == owner &&
      other.repo == repo &&
      other.port == port;

  @override
  int get hashCode => Object.hash(kind, host, owner, repo, port);

  @override
  String toString() => 'ForgeHost($kind, $host, $projectPath)';
}

/// The public clouds, keyed by the name a remote carries. Always recognised;
/// anything else must be registered as a [ForgeServer].
const _cloudHosts = <String, ForgeServer>{
  'github.com': kGithubCloud,
  'www.github.com': kGithubCloud,
  'gitlab.com': kGitlabCloud,
  'www.gitlab.com': kGitlabCloud,
};

/// `git@host:path`, the form ssh remotes are usually written in. A
/// `scheme://` URL never reaches this regex at all — [resolveForgeHost]
/// routes anything containing `://` through [Uri] first — so the lookahead
/// only has to rule out a colon immediately followed by a slash in whatever
/// scp-like string made it this far.
final _scpLike = RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):(?!/)(\S+)$');

/// Schemes a git remote can carry that still name a host.
const _schemes = {'https', 'http', 'ssh', 'git'};

/// The forge coordinates for [remoteUrl], or null when it names no supported
/// forge — a local path, an unknown host, or something unparseable. Null is an
/// ordinary answer here, not a failure.
///
/// github.com and gitlab.com are always known; a self-hosted installation is
/// known once it is among [servers]. A remote matches a server by host name
/// alone, since git and the web are routinely served on different ports.
ForgeHost? resolveForgeHost(
  String remoteUrl, {
  Iterable<ForgeServer> servers = const [],
}) {
  final raw = remoteUrl.trim();
  if (raw.isEmpty) return null;

  String host;
  String path;
  if (raw.contains('://')) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !_schemes.contains(uri.scheme)) return null;
    host = uri.host;
    path = uri.path;
  } else {
    final scp = _scpLike.firstMatch(raw);
    if (scp == null) return null;
    host = scp.group(1)!;
    path = scp.group(2)!;
  }

  final name = host.toLowerCase();
  final server =
      _cloudHosts[name] ?? servers.where((s) => s.host == name).firstOrNull;
  if (server == null) return null;
  final kind = server.kind;

  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segments.length < 2) return null;
  // GitHub addresses a repository as owner/repo and nothing deeper, so extra
  // segments mean this is a browser URL rather than a remote. GitLab nests
  // groups arbitrarily, and every group before the last is part of the owner.
  if (kind == ForgeKind.github && segments.length != 2) return null;

  var repo = segments.last;
  if (repo.endsWith('.git')) {
    repo = repo.substring(0, repo.length - 4);
  }
  if (repo.isEmpty) return null;

  final owner = segments.sublist(0, segments.length - 1);
  // owner and repo are spliced straight into an API path, and Uri resolves a
  // `.` or `..` segment away rather than sending it — so a remote carrying
  // one addresses a different project under this user's token. Stripping
  // `.git` can produce one that was not there a moment ago (`...git` leaves
  // `..`), which is why repo is checked after that and not before. No remote
  // a forge would accept contains either, so refusing costs nothing real.
  if ([...owner, repo].any((s) => s == '.' || s == '..')) return null;

  return ForgeHost(
    kind: kind,
    host: server.host,
    port: server.port,
    owner: owner.join('/'),
    repo: repo,
  );
}
