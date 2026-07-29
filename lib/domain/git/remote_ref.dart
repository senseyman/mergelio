// Tells a remote-tracking ref (`origin/main`) apart from a local branch that
// merely contains a slash (`feature/origin`). Only the repository's configured
// remote names can make that call, so they are passed in rather than guessed.

/// Splits [ref] into its remote name and branch, or null when [ref] is not a
/// remote-tracking ref of one of [remotes]. Longer remote names are tried
/// first, so a remote called `origin/mirror` is not shadowed by `origin`.
(String, String)? splitRemoteRef(String ref, Iterable<String> remotes) {
  final byLength = remotes.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final r in byLength) {
    final prefix = '$r/';
    if (ref.startsWith(prefix) && ref.length > prefix.length) {
      return (r, ref.substring(prefix.length));
    }
  }
  return null;
}

/// Whether [ref] names a remote-tracking branch of one of [remotes].
bool isRemoteRef(String ref, Iterable<String> remotes) =>
    splitRemoteRef(ref, remotes) != null;
