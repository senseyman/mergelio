import 'git_toolchain.dart';

/// What to do with a commit during an interactive rebase — or, for [exec] and
/// [breakpoint], a step of the plan that is not a commit at all: a command run
/// between commits, and a stop that hands the repository back to the user.
enum RebaseAction { pick, reword, squash, fixup, drop, exec, breakpoint }

/// The actions a commit row can take; [RebaseAction.exec] and
/// [RebaseAction.breakpoint] are rows of their own, never a commit's choice.
const rebaseCommitActions = [
  RebaseAction.pick,
  RebaseAction.reword,
  RebaseAction.squash,
  RebaseAction.fixup,
  RebaseAction.drop,
];

/// One step of the rebase plan, in apply order (oldest first). [message] is
/// the new message for a [RebaseAction.reword], and [sign] re-signs the
/// rewritten commit so a reword does not silently strip a signature.
class RebaseStep {
  final String sha;
  final RebaseAction action;
  final String message;
  final bool sign;

  /// For a reword: skip the commit hooks when the new message is committed.
  final bool noVerify;

  /// The shell command of an exec step; empty for every other step.
  final String command;

  /// Stable identity within one plan. A commit is its sha; exec and break
  /// steps have no sha, so whoever adds them names them.
  final String id;

  const RebaseStep(
    this.sha,
    this.action, {
    this.message = '',
    this.sign = false,
    this.noVerify = false,
  }) : command = '',
       id = sha;

  /// Runs [command] in the working tree at this point of the sequence. A
  /// non-zero exit pauses the rebase there.
  const RebaseStep.exec(this.command, {required this.id})
    : sha = '',
      action = RebaseAction.exec,
      message = '',
      sign = false,
      noVerify = false;

  /// Pauses the rebase at this point so the user can look around, amend, and
  /// continue.
  const RebaseStep.breakpoint({required this.id})
    : sha = '',
      action = RebaseAction.breakpoint,
      message = '',
      sign = false,
      noVerify = false,
      command = '';

  bool get isCommit =>
      action != RebaseAction.exec && action != RebaseAction.breakpoint;

  /// This commit step with [action] (and, when given, [message]) swapped in.
  /// Exec and break steps have no sha to carry over.
  RebaseStep withAction(RebaseAction action, {String? message}) {
    assert(isCommit, 'withAction on a ${this.action.name} step');
    return RebaseStep(
      sha,
      action,
      message: message ?? this.message,
      sign: sign,
      noVerify: noVerify,
    );
  }
}

/// What the rebase editor hands back: the plan, and whether branches stacked
/// on its commits should move with them.
class RebasePlan {
  final List<RebaseStep> steps;
  final bool updateRefs;
  const RebasePlan(this.steps, {this.updateRefs = false});
}

/// Builds a git rebase todo from [steps] (oldest-first). Reword is expressed as
/// `pick` followed by an `exec git commit --amend` so no interactive editor is
/// needed; drop is omitted; squash/fixup/exec/break map directly.
///
/// [updateRefs] maps a commit sha to the local branches pointing at it. Each
/// gets an `update-ref` line once its commit — and the squash/fixup run folded
/// into it — has been replayed, so a branch stacked on the rebased one follows
/// its commit. A dropped commit's branches stay at that place in the stack.
String buildRebaseTodo(
  List<RebaseStep> steps, {
  Map<String, List<String>> updateRefs = const {},
}) {
  final lines = <String>[];
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
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
          '$_rewordExec${_shellQuote(_escapeNewlines(s.message))} '
          '| git commit --amend ${s.sign ? '-S ' : ''}'
          '${s.noVerify ? '--no-verify ' : ''}-F -',
        );
      case RebaseAction.squash:
        lines.add('squash ${s.sha}');
      case RebaseAction.fixup:
        lines.add('fixup ${s.sha}');
      case RebaseAction.drop:
        // Omit dropped commits entirely.
        break;
      case RebaseAction.exec:
        lines.add('exec ${s.command.trim()}');
      case RebaseAction.breakpoint:
        lines.add('break');
    }
    if (!s.isCommit) continue;
    // A squash or fixup below this commit is still part of it, so a branch on
    // either one lands on the folded result — and only once it is complete.
    var end = i;
    while (end + 1 < steps.length && _folds(steps[end + 1].action)) {
      end++;
    }
    final branches = [
      for (final c in steps.sublist(i, end + 1)) ...?updateRefs[c.sha],
    ];
    if (branches.isEmpty) continue;
    for (final f in steps.sublist(i + 1, end + 1)) {
      lines.add('${f.action.name} ${f.sha}');
    }
    i = end;
    for (final b in branches) {
      lines.add('update-ref refs/heads/$b');
    }
  }
  return '${lines.join('\n')}\n';
}

bool _folds(RebaseAction a) =>
    a == RebaseAction.squash || a == RebaseAction.fixup;

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

/// Whether [todo] runs a command the user added — which may take any length
/// of time — rather than only the quick amends a reword is made of.
bool todoRunsUserExec(String todo) => todo
    .split('\n')
    .any((l) => l.startsWith('exec ') && !_rewordLine.hasMatch(l));

/// How every reword's exec line starts.
const _rewordExec = "exec printf '%b' ";

/// A whole reword line, as [buildRebaseTodo] writes it: the quoted message
/// piped into the amend, and nothing else. A user command that merely starts
/// the same way is still the user's.
final _rewordLine = RegExp(
  r"^exec printf '%b' '(?:[^']|'\\'')*' \| git commit --amend "
  r'(?:-S )?(?:--no-verify )?-F -$',
);

/// Whether git [gitVersion] understands an `update-ref` line in a todo (added
/// in git 2.38). Older git rejects the whole todo — after it has already
/// created its rebase state, leaving the repository mid-rebase.
bool supportsUpdateRefTodo(String gitVersion) =>
    gitVersionAtLeast(gitVersion, 2, 38);

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

/// Rewrites [steps] to match [preset], keeping sha order and messages. The
/// first commit is always picked — nothing above it survives to squash into —
/// so a single-commit plan comes back as a plain pick for every preset. Exec
/// and break steps are not commits and stay exactly where they are.
List<RebaseStep> applyPreset(List<RebaseStep> steps, RebasePreset preset) {
  final out = <RebaseStep>[];
  var seenCommit = false;
  for (final s in steps) {
    if (!s.isCommit) {
      out.add(s);
      continue;
    }
    out.add(
      RebaseStep(
        s.sha,
        !seenCommit
            ? RebaseAction.pick
            : switch (preset) {
                RebasePreset.asIs => RebaseAction.pick,
                RebasePreset.squashAll => RebaseAction.squash,
                RebasePreset.squashKeepFirst => RebaseAction.fixup,
              },
        message: s.message,
        sign: s.sign,
      ),
    );
    seenCommit = true;
  }
  return out;
}

/// Why [steps] cannot be handed to git, or null when the plan is runnable.
/// The first commit that survives has nothing above it to merge into, so git
/// rejects the whole todo with "Cannot 'squash' without a previous commit"
/// before applying anything. Exec and break steps do not count as that commit.
/// An exec has to be one non-empty line: the todo is line-oriented, so a second
/// line would reach git as an instruction of its own.
String? rebasePlanError(List<RebaseStep> steps) {
  for (final s in steps) {
    if (s.action != RebaseAction.exec) continue;
    if (s.command.trim().isEmpty) return 'An exec step has no command to run.';
    if (s.command.contains('\n') || s.command.contains('\r')) {
      return 'An exec command has to fit on one line.';
    }
  }
  for (final s in steps) {
    if (!s.isCommit || s.action == RebaseAction.drop) continue;
    if (_folds(s.action)) {
      return 'The first commit kept in the plan cannot be squashed or fixed '
          'up — there is no commit above it to merge into.';
    }
    return null;
  }
  return null;
}

// --- Autosquash ----------------------------------------------------------------

const _autosquashPrefixes = ['fixup! ', 'squash! ', 'amend! '];

/// Whether [subject] asks to be folded into another commit, and into which:
/// `fixup! <target>` and `squash! <target>`. Stacked prefixes (a fixup of a
/// fixup) keep the outer kind and point at the innermost target, the way git
/// reads them. `amend! ` is not handled here: it replaces the target's message
/// as well, which a plain fixup cannot express.
({RebaseAction kind, String target})? autosquashSubject(String subject) {
  final RebaseAction kind;
  if (subject.startsWith('fixup! ')) {
    kind = RebaseAction.fixup;
  } else if (subject.startsWith('squash! ')) {
    kind = RebaseAction.squash;
  } else {
    return null;
  }
  var rest = subject;
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final p in _autosquashPrefixes) {
      if (rest.startsWith(p)) {
        rest = rest.substring(p.length);
        stripped = true;
      }
    }
  }
  if (rest.trim().isEmpty) return null;
  return (kind: kind, target: rest);
}

/// [autosquash] output: the reordered plan, and which commit each moved one
/// was paired with (moved id → target id).
typedef AutosquashResult = ({
  List<RebaseStep> steps,
  Map<String, String> pairs,
});

/// Moves every `fixup!`/`squash!` commit directly under the commit it names,
/// after any earlier ones paired with the same target, and marks it fixup or
/// squash. Reads each commit's [RebaseStep.message] as its subject.
///
/// The target is looked for among commits *above* the candidate only — the
/// same rule as git: an exact subject first, then a sha prefix, then a subject
/// prefix. A candidate with no target stays where it is, still a pick. Exec and
/// break steps that followed the target now follow the folded result, so a
/// test run after a commit tests it with its fixes in.
AutosquashResult autosquash(List<RebaseStep> steps) {
  // Each commit with the non-commit steps that follow it, so moving a commit
  // never strands an exec the user put under something else.
  final groups = <List<RebaseStep>>[];
  final lead = <RebaseStep>[];
  for (final s in steps) {
    if (s.isCommit) {
      groups.add([s]);
    } else if (groups.isEmpty) {
      lead.add(s);
    } else {
      groups.last.add(s);
    }
  }

  final pairs = <String, String>{};
  final order = <List<RebaseStep>>[];
  // The group each commit ended up in: a folded commit joins its target's.
  final groupOf = <String, List<RebaseStep>>{};
  for (final g in groups) {
    final c = g.first;
    final want = autosquashSubject(c.message);
    final target = want == null ? null : _findTarget(order, want.target);
    if (want == null || target == null) {
      order.add(g);
      groupOf[c.id] = g;
      continue;
    }
    final into = groupOf[target.id]!;
    pairs[c.id] = target.id;
    groupOf[c.id] = into;
    into.insert(
      into.lastIndexWhere((s) => s.isCommit) + 1,
      c.withAction(want.kind),
    );
    into.addAll(g.skip(1));
  }
  return (steps: [...lead, for (final g in order) ...g], pairs: pairs);
}

RebaseStep? _findTarget(List<List<RebaseStep>> above, String target) {
  final commits = [
    for (final g in above)
      for (final s in g)
        if (s.isCommit) s,
  ];
  for (final c in commits) {
    if (c.message == target) return c;
  }
  for (final c in commits) {
    if (c.sha.isNotEmpty && c.sha.startsWith(target)) return c;
  }
  for (final c in commits) {
    if (c.message.startsWith(target)) return c;
  }
  return null;
}

/// Takes back an [autosquash]: every commit in [paired] returns to the place it
/// had in [original] — right after the commit that preceded it there — as a
/// plain pick. Everything else, including exec and break steps added since,
/// stays where it is now.
List<RebaseStep> undoAutosquash(
  List<RebaseStep> steps,
  List<RebaseStep> original,
  Set<String> paired,
) {
  final out = [
    for (final s in steps)
      if (!paired.contains(s.id)) s,
  ];
  final byId = {for (final s in steps) s.id: s};
  final commits = [
    for (final s in original)
      if (s.isCommit) s,
  ];
  for (var i = 0; i < commits.length; i++) {
    final s = byId[commits[i].id];
    if (s == null || !paired.contains(s.id)) continue;
    final back = s.withAction(RebaseAction.pick);
    if (i == 0) {
      final firstCommit = out.indexWhere((x) => x.isCommit);
      out.insert(firstCommit < 0 ? out.length : firstCommit, back);
      continue;
    }
    final prev = out.indexWhere((x) => x.id == commits[i - 1].id);
    out.insert(prev + 1, back);
  }
  return out;
}

/// The message git's own `commit --fixup` writes for a fix to [subject].
String fixupSubject(String subject) => 'fixup! $subject';

// --- Stops ----------------------------------------------------------------------

/// What a [RebaseStop] is.
enum RebaseStopKind { breakpoint, exec, reword }

/// Why a rebase is sitting still when no file is conflicted: a break the plan
/// asked for, an exec whose [command] failed, or a reword whose new message a
/// commit hook refused.
class RebaseStop {
  final RebaseStopKind kind;

  /// The failed command, for [RebaseStopKind.exec]; null otherwise.
  final String? command;
  const RebaseStop.exec(String this.command) : kind = RebaseStopKind.exec;
  const RebaseStop.breakpoint()
    : kind = RebaseStopKind.breakpoint,
      command = null;
  const RebaseStop.reword() : kind = RebaseStopKind.reword, command = null;

  bool get isExec => kind == RebaseStopKind.exec;

  /// Whether a step failed, with output worth showing, as opposed to a pause
  /// the plan asked for.
  bool get failed => kind != RebaseStopKind.breakpoint;

  @override
  bool operator ==(Object other) =>
      other is RebaseStop && other.kind == kind && other.command == command;

  @override
  int get hashCode => Object.hash(kind, command);

  @override
  String toString() => 'RebaseStop.${kind.name}(${command ?? ''})';
}

/// Reads the stop out of git's `done` file (the steps already run, the one it
/// stopped on last). Null when the last step was not a break or an exec — a
/// conflicted or empty pick, which has its own handling.
RebaseStop? parseRebaseStop(String done) {
  final lines = [
    for (final l in done.split('\n'))
      if (l.trim().isNotEmpty && !l.trimLeft().startsWith('#')) l.trim(),
  ];
  if (lines.isEmpty) return null;
  final last = lines.last;
  if (last == 'break' || last == 'b') return const RebaseStop.breakpoint();
  if (_rewordLine.hasMatch(last)) return const RebaseStop.reword();
  for (final verb in const ['exec ', 'x ']) {
    if (last.startsWith(verb)) {
      return RebaseStop.exec(last.substring(verb.length).trim());
    }
  }
  return null;
}
