/// Why a set of clone options can't be used as they stand.
enum CloneProblem { badDepth, badBranch }

/// What the clone dialog can ask of `git clone` beyond URL and destination.
class CloneOptions {
  /// Commits of history to fetch; null clones all of it.
  final int? depth;

  /// Fetch commits and trees now, file contents on demand
  /// (`--filter=blob:none`).
  final bool blobless;

  /// Branch to check out instead of the remote's default; null or blank
  /// leaves the choice to the remote.
  final String? branch;

  /// Fetch only [branch] (or the remote's default when none is named).
  final bool singleBranch;

  /// Clone the submodules too. On by default: a superproject cloned without
  /// them comes up with empty directories where its submodules should be.
  final bool submodules;

  const CloneOptions({
    this.depth,
    this.blobless = false,
    this.branch,
    this.singleBranch = false,
    this.submodules = true,
  });

  String? get _branch {
    final b = branch?.trim();
    return (b == null || b.isEmpty) ? null : b;
  }

  /// The first thing that would make git refuse these options, or null.
  CloneProblem? get problem {
    if (depth != null && depth! < 1) return CloneProblem.badDepth;
    final b = _branch;
    if (b != null && !_validBranchName(b)) return CloneProblem.badBranch;
    return null;
  }
}

/// git's own branch-name rules (`check-ref-format --branch`), so a bad name
/// is caught in the dialog instead of by a failed clone. A leading `-` is
/// refused too: `--branch` comes before the `--` separator, and such a name
/// would be read as an option.
bool _validBranchName(String b) {
  if (b.startsWith('-') || b.startsWith('/')) return false;
  if (b.endsWith('/') || b.endsWith('.')) return false;
  if (b.contains('..') || b.contains('//') || b.contains('@{')) return false;
  if (b.contains(RegExp(r'[\x00-\x20\x7f~^:?*\[\\]|\s'))) return false;
  return b
      .split('/')
      .every((part) => !part.startsWith('.') && !part.endsWith('.lock'));
}

/// A depth typed into the dialog: a positive whole number, else null.
int? parseDepth(String text) {
  final n = int.tryParse(text.trim());
  return (n == null || n < 1) ? null : n;
}

/// Whether git would read [source] as a path on this machine rather than a
/// URL. Mirrors git's own rule: anything with `://` is a URL, and a colon
/// before the first slash makes it scp-like ssh (`host:repo`) — except a
/// single drive letter, which is a Windows path.
bool isLocalCloneSource(String source) {
  final s = source.trim();
  if (s.contains('://')) return false;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(s)) return true;
  final colon = s.indexOf(':');
  if (colon < 0) return true;
  final slash = s.indexOf('/');
  return slash >= 0 && slash < colon;
}

/// The full `git clone` argv for [url] into [target].
List<String> cloneArgs(String url, String target, CloneOptions o) {
  final branch = o._branch;
  return [
    'clone',
    if (o.submodules) '--recurse-submodules',
    // From a plain path git copies the object store directly and ignores
    // --depth and --filter with only a warning; the regular transport
    // honours both.
    if ((o.depth != null || o.blobless) && isLocalCloneSource(url))
      '--no-local',
    if (o.depth != null) ...['--depth', '${o.depth}'],
    if (o.blobless) '--filter=blob:none',
    if (branch != null) ...['--branch', branch],
    if (o.singleBranch)
      '--single-branch'
    // --depth narrows to one branch on its own; keep the checkbox the truth.
    else if (o.depth != null)
      '--no-single-branch',
    // The URL is user input: never let git read it as an option.
    '--',
    url,
    target,
  ];
}
