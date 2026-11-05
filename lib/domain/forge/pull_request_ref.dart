// Where a forge publishes a pull request's head as a git ref, and the local
// branch Mergelio checks it out onto. Pure string work: head refs and local
// branches are built from the number alone, so nothing a forge sent can shape
// them. The one name a forge does supply, the target branch, is validated
// before it becomes a ref.

import '../git/ref_names.dart';
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

/// The ref origin carries for the branch a request targets, which is what
/// its diff is read against.
///
/// Unlike the head ref, the name here is whatever the forge sent, and it is
/// handed to `git fetch` as a refspec. A colon would add a destination and
/// write a local ref, a leading `+` would force one, and git refuses every
/// other name rejected here anyway, so nothing that could work is lost.
String pullRequestBaseRef(String targetBranch) {
  if (targetBranch.startsWith('+') || !isValidBranchName(targetBranch)) {
    // The name is left out of the message: it came from the forge.
    throw ArgumentError('not a usable branch name');
  }
  return 'refs/heads/$targetBranch';
}

void _checkNumber(int number) {
  if (number < 1) {
    throw ArgumentError.value(number, 'number', 'must be positive');
  }
}

/// How checking out a pull request went.
enum PullRequestCheckoutOutcome {
  /// The request is checked out at its current head.
  done,

  /// The local branch has commits the request does not — it was
  /// force-pushed or rebased — so nothing was changed. Moving the branch
  /// would drop those commits, which only the person can agree to.
  diverged,

  /// Something refused or went wrong, and was already reported.
  failed,
}

class PullRequestCheckout {
  final PullRequestCheckoutOutcome outcome;

  /// With [PullRequestCheckoutOutcome.diverged], how many commits the local
  /// branch has that the request does not.
  final int localOnly;

  const PullRequestCheckout(this.outcome, {this.localOnly = 0});
}
