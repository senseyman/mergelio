/// What to do with a commit during an interactive rebase.
enum RebaseAction { pick, reword, squash, fixup, drop }

/// One commit in the rebase plan, in apply order (oldest first). [message] is
/// the new message for a [RebaseAction.reword], and [sign] re-signs the
/// rewritten commit so a reword does not silently strip a signature.
class RebaseStep {
  final String sha;
  final RebaseAction action;
  final String message;
  final bool sign;
  const RebaseStep(
    this.sha,
    this.action, {
    this.message = '',
    this.sign = false,
  });
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
        // The message is piped in rather than passed with -m: a todo file is
        // line-oriented, so a message with a body would otherwise split the
        // exec across lines git reads as separate instructions. `printf %b`
        // turns the escaped one-liner back into the real multi-line message.
        lines.add(
          "exec printf '%b' ${_shellQuote(_escapeNewlines(s.message))} "
          '| git commit --amend ${s.sign ? '-S ' : ''}-F -',
        );
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

/// Folds a message onto one line for `printf %b`. Existing backslashes are
/// doubled first so printf renders them literally instead of reading them as
/// escapes of their own.
String _escapeNewlines(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\n');
