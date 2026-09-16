// Turns a git remote URL into the forge coordinates an API call needs. Pure
// string work: the same remote must resolve identically whether it was written
// as https, ssh:// or scp-style, because a repository's remotes often mix them.

/// Which forge a host belongs to. Only public clouds are recognised.
enum ForgeKind { github, gitlab }

/// A repository as a forge addresses it.
class ForgeHost {
  final ForgeKind kind;

  /// Canonical API host, with any `www.` prefix and port removed.
  final String host;

  /// Everything before the repository name. A single account on GitHub; on
  /// GitLab this may be several `/`-separated groups deep.
  final String owner;

  final String repo;

  const ForgeHost({
    required this.kind,
    required this.host,
    required this.owner,
    required this.repo,
  });

  /// The project as git and the web UI spell it. Callers that need an API path
  /// segment must escape this themselves; it is stored unescaped.
  String get projectPath => '$owner/$repo';

  @override
  bool operator ==(Object other) =>
      other is ForgeHost &&
      other.kind == kind &&
      other.host == host &&
      other.owner == owner &&
      other.repo == repo;

  @override
  int get hashCode => Object.hash(kind, host, owner, repo);

  @override
  String toString() => 'ForgeHost($kind, $host, $projectPath)';
}

/// Hosts recognised as a forge, keyed by the name a remote carries.
const _hosts = <String, ForgeKind>{
  'github.com': ForgeKind.github,
  'www.github.com': ForgeKind.github,
  'gitlab.com': ForgeKind.gitlab,
  'www.gitlab.com': ForgeKind.gitlab,
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
ForgeHost? resolveForgeHost(String remoteUrl) {
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

  final kind = _hosts[host.toLowerCase()];
  if (kind == null) return null;

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

  return ForgeHost(
    kind: kind,
    host: host.toLowerCase().startsWith('www.')
        ? host.toLowerCase().substring(4)
        : host.toLowerCase(),
    owner: segments.sublist(0, segments.length - 1).join('/'),
    repo: repo,
  );
}
