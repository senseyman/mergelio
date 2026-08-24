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

/// A whole-branch answer to "what should this rebase do?", so the common cases
/// need one choice instead of one choice per commit.
enum RebasePreset { asIs, squashAll, squashKeepFirst }

/// Rewrites [steps] to match [preset], keeping sha order and messages. A plan
/// of fewer than two commits has nothing to squash into, so it comes back as
/// plain picks whichever preset is asked for.
List<RebaseStep> applyPreset(List<RebaseStep> steps, RebasePreset preset) => [
  for (var i = 0; i < steps.length; i++)
    RebaseStep(
      steps[i].sha,
      i == 0 || steps.length < 2
          ? RebaseAction.pick
          : switch (preset) {
              RebasePreset.asIs => RebaseAction.pick,
              RebasePreset.squashAll => RebaseAction.squash,
              RebasePreset.squashKeepFirst => RebaseAction.fixup,
            },
      message: steps[i].message,
      sign: steps[i].sign,
    ),
];

/// Why [steps] cannot be handed to git, or null when the plan is runnable.
/// The first commit that survives has nothing above it to merge into, so git
/// rejects the whole todo with "Cannot 'squash' without a previous commit"
/// before applying anything.
String? rebasePlanError(List<RebaseStep> steps) {
  for (final s in steps) {
    if (s.action == RebaseAction.drop) continue;
    if (s.action == RebaseAction.squash || s.action == RebaseAction.fixup) {
      return 'The first commit kept in the plan cannot be squashed or fixed '
          'up — there is no commit above it to merge into.';
    }
    return null;
  }
  return null;
}
