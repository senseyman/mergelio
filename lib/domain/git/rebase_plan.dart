/// What to do with a commit during an interactive rebase.
enum RebaseAction { pick, reword, squash, fixup, drop }

/// One commit in the rebase plan, in apply order (oldest first). [message] is
/// the new message for a [RebaseAction.reword].
class RebaseStep {
  final String sha;
  final RebaseAction action;
  final String message;
  const RebaseStep(this.sha, this.action, {this.message = ''});
}

/// Builds a git rebase todo from [steps] (oldest-first). Reword is expressed as
/// `pick` followed by an `exec git commit --amend` so no interactive editor is
/// needed; drop is omitted; squash/fixup map directly. Returns null when the
/// plan is a no-op (all picks in original order is the caller's concern; here
/// null means nothing to apply, e.g. everything dropped).
String buildRebaseTodo(List<RebaseStep> steps) {
  final lines = <String>[];
  for (final s in steps) {
    switch (s.action) {
      case RebaseAction.pick:
        lines.add('pick ${s.sha}');
      case RebaseAction.reword:
        lines.add('pick ${s.sha}');
        lines.add('exec git commit --amend -m ${_shellQuote(s.message)}');
      case RebaseAction.squash:
        lines.add('squash ${s.sha}');
      case RebaseAction.fixup:
        lines.add('fixup ${s.sha}');
      case RebaseAction.drop:
        // Omit dropped commits entirely.
        break;
    }
  }
  return '${lines.join('\n')}\n';
}

/// True when [steps] would not change history (every commit picked, in order).
bool isNoOpPlan(List<RebaseStep> original, List<RebaseStep> steps) {
  if (original.length != steps.length) return false;
  for (var i = 0; i < steps.length; i++) {
    if (steps[i].sha != original[i].sha ||
        steps[i].action != RebaseAction.pick) {
      return false;
    }
  }
  return true;
}

String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
