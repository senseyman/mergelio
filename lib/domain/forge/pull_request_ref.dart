// Where a forge publishes a pull request's head as a git ref, and the local
// branch Mergelio checks it out onto. Pure string work: the number is the only
// input, so nothing a forge sent can shape a ref name.

import 'forge_host.dart';

/// The ref origin carries for pull request (merge request) [number]'s head.
///
/// Both forges publish it for every request, including one opened from a
/// fork, so fetching it needs neither the fork's URL nor a token.
String pullRequestHeadRef(ForgeKind kind, int number) {
  _checkNumber(number);
  return switch (kind) {
    ForgeKind.github => 'refs/pull/$number/head',
    ForgeKind.gitlab => 'refs/merge-requests/$number/head',
  };
}

/// The local branch pull request (merge request) [number] is checked out as:
/// `pr/<n>` on GitHub, `mr/<n>` on GitLab, matching what each forge calls it.
String pullRequestLocalBranch(ForgeKind kind, int number) {
  _checkNumber(number);
  return switch (kind) {
    ForgeKind.github => 'pr/$number',
    ForgeKind.gitlab => 'mr/$number',
  };
}

void _checkNumber(int number) {
  if (number < 1) {
    throw ArgumentError.value(number, 'number', 'must be positive');
  }
}
