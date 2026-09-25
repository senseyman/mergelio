import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/bisect.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/bisect.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/unsaved_guard.dart';
import '../common/dialogs.dart';
import '../shell/repo_op_dialogs.dart';
import 'bisect_run_dialog.dart';
import 'graph_rail.dart';

/// Persistent strip above the commit list while a bisect is running: how
/// the hunt is going, and the verdict buttons to move it along.
///
/// Git's own on-disk state drives every branch here, so this renders
/// correctly whether the bisect was started from Mergelio or from a
/// terminal. `git bisect start` alone leaves `refs/bisect` empty — no bad
/// mark yet, so nothing to halve — which is a state of its own, not a
/// half-formed "running" with counts git never computed.
///
/// Laid out with [Wrap] rather than [Row]: the graph panel is the window
/// minus the sidebar and detail panel, and the running row's four buttons
/// plus counts run out of width well before the window itself gets narrow.
///
/// Stateful so it can register a quit guard with [unsavedGuardsProvider]
/// while a bisect is in progress and drop it again when there is none.
/// Quitting — or closing this repository's tab — checks that guard first;
/// without it the app would happily leave the repository on a detached HEAD
/// with no warning, which is the one edge this whole feature cannot afford
/// to get wrong.
class BisectBar extends ConsumerStatefulWidget {
  final String repoPath;
  final void Function(String sha) onJumpToCommit;

  const BisectBar({
    super.key,
    required this.repoPath,
    required this.onJumpToCommit,
  });

  @override
  ConsumerState<BisectBar> createState() => _BisectBarState();
}

class _BisectBarState extends ConsumerState<BisectBar> {
  // Held rather than read through `ref`, which is off limits by the time
  // this bar is being torn down.
  late final UnsavedGuards _guards;

  /// Drops this bar's own registration, and null while it holds none. Other
  /// guards on the same repository — an editor pane's, across a switch
  /// between Files and the graph — are none of this bar's business.
  DropGuard? _dropGuard;

  @override
  void initState() {
    super.initState();
    _guards = ref.read(unsavedGuardsProvider);
  }

  @override
  void dispose() {
    // A guard that outlives this widget would block the user from ever
    // quitting the repository again — far worse than the detached HEAD it
    // exists to warn about.
    _dropGuard?.call();
    super.dispose();
  }

  /// Registers or drops the guard to match whether a bisect exists at all.
  /// A finished bisect still sits on a detached HEAD until it is reset, so
  /// only `state == null` — no bisect, of any kind — drops the guard.
  ///
  /// Only ever called with an answer git actually gave: an unknown read
  /// leaves the guard exactly as it was.
  void _syncGuard({required bool active}) {
    if (active == (_dropGuard != null)) return;
    if (active) {
      _dropGuard = _guards.register(widget.repoPath, _confirmQuit);
    } else {
      _dropGuard?.call();
      _dropGuard = null;
    }
  }

  /// The first bad sha this bar has already moved the cursor onto, so the
  /// move happens once per answer and never again.
  ///
  /// Selecting on every build would fight the user: the bar rebuilds on every
  /// repository refresh, and each rebuild would drag the cursor back off
  /// whatever row they had clicked since. Cleared only when git gives a
  /// definite answer with no first bad commit in it — a reset, or a fresh
  /// hunt — so the next hunt to land is auto-selected in its turn while an
  /// unreadable moment mid-hunt is not mistaken for one.
  String? _autoSelected;

  void _trackFirstBad(String? firstBad) {
    if (firstBad == null) {
      _autoSelected = null;
      return;
    }
    if (firstBad == _autoSelected) return;
    // Recorded before the frame ends rather than inside the callback, so a
    // second build in the same frame cannot queue the same move twice.
    _autoSelected = firstBad;
    // Writing a provider during a build is an error, and the hunt landing is
    // exactly the moment a build is running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedCommitProvider.notifier).state = firstBad;
    });
  }

  /// The verdict trail as last fetched, and null until a fetch has come back
  /// with one. [_logFailed] tells that apart from a fetch that failed, which
  /// also leaves nothing to show but means something quite different.
  String? _log;
  bool _logFailed = false;

  /// Whether the trail is on screen, and whether a fetch for it is in flight.
  /// The panel only appears once a fetch has returned, so a slow read shows a
  /// disabled button rather than an empty box that fills in later.
  bool _logOpen = false;
  bool _logBusy = false;

  /// How the most recently completed `git bisect run` ended, so the running
  /// row can explain a failure in its own words instead of leaving git's raw
  /// message unaccounted for. Null before any run, and cleared the moment a
  /// fresh one starts so a stale explanation cannot outlive it.
  BisectRunOutcome? _lastRunOutcome;

  /// Opens the run dialog and, if a command comes back, hands it to git.
  ///
  /// Cancelling or dismissing the dialog leaves everything as it was: no
  /// outcome to show, nothing running. [bisectRunProvider] is what drives the
  /// running row while the command is in flight; this only has to keep the
  /// outcome once it lands.
  Future<void> _run(RepoActions actions) async {
    final command = await showBisectRunDialog(context);
    if (command == null || !mounted) return;
    setState(() => _lastRunOutcome = null);
    final outcome = await actions.runBisect(command);
    if (!mounted) return;
    setState(() => _lastRunOutcome = outcome);
  }

  /// Explains an outcome the running row cannot leave to git's own message.
  ///
  /// [BisectRunOutcome.finished] needs nothing here: the state itself moves
  /// to the finished card, which is its own explanation.
  ///
  /// [BisectRunOutcome.failed] is the failure nobody could name, so it is the
  /// one the action layer toasts — in git's own words, which is all there is
  /// to go on. Repeating it here would read as two separate problems.
  String? _outcomeMessage(AppLocalizations l, BisectRunOutcome? outcome) =>
      switch (outcome) {
        null => null,
        BisectRunOutcome.finished => null,
        BisectRunOutcome.failed => null,
        BisectRunOutcome.exhausted => l.bisectRunExhausted,
        BisectRunOutcome.commandUnrunnable => l.bisectRunUnrunnable,
        BisectRunOutcome.treeDirtied => l.bisectRunTreeDirtied,
        BisectRunOutcome.cancelled => l.bisectRunCancelled,
      };

  Future<void> _toggleLog(RepoActions actions) async {
    if (_logOpen) {
      setState(() => _logOpen = false);
      return;
    }
    if (_logBusy) return;
    setState(() => _logBusy = true);
    // Re-fetched on every open rather than cached: verdicts are recorded
    // between one open and the next, and a stale trail is worse than none.
    final log = await actions.bisectLog();
    if (!mounted) return;
    setState(() {
      _logBusy = false;
      _logOpen = true;
      _log = log;
      _logFailed = log == null;
    });
  }

  Future<bool> _confirmQuit() async {
    if (!mounted) return false;
    final choice = await showBisectQuitDialog(context);
    switch (choice) {
      case BisectQuitChoice.cancel:
        return false;
      case BisectQuitChoice.quitAnyway:
        return true;
      case BisectQuitChoice.reset:
        await ref.read(repoActionsProvider(widget.repoPath)).resetBisect();
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = ref.watch(bisectStateProvider(widget.repoPath));
    final state = read.bisect;
    // The guard tracks the last thing git actually said, not the last thing
    // that happened. An unknown read — a first load still in flight, or one
    // that failed — is not a repository known to be clear of a bisect, so it
    // never drops a guard; but it is not one known to be in a bisect either,
    // so it must not arm one. Arming on it would warn about a hunt that was
    // never running the moment a tab is opened and closed again, and would
    // make a repository whose reads always fail prompt on every quit with
    // nothing for the dialog's Reset to undo.
    if (!read.unknown) {
      _syncGuard(active: state != null);
      // Same rule for the cursor: only an answer git gave moves it, so a
      // failed read mid-hunt cannot be read as "the hunt is over" and a later
      // successful one cannot re-select a commit the user has already moved
      // away from.
      _trackFirstBad(state?.firstBad);
    }
    final l = AppLocalizations.of(context);
    final t = context.tokens;

    if (read.unknown) {
      // A failed read gets a line saying so; one merely still in flight gets
      // nothing, so opening a repository does not flash a warning that the
      // next frame withdraws.
      return read.hasError
          ? _wrap(t, (_) => [Text(l.bisectUnreadable)])
          : _hidden;
    }
    if (state == null) return _hidden;

    final actions = ref.read(repoActionsProvider(widget.repoPath));
    final hasBad = state.marks.any((m) => m.kind == BisectKind.bad);
    return _wrap(
      t,
      (width) => state.finished
          ? _finished(l, t, state, actions, width)
          // No bad mark yet: git has nothing to halve, whether that's because
          // no marks exist at all or only good ones were typed at a terminal
          // before a bad one. Both read the same to the person using the bar.
          : !hasBad
          ? _noMarks(l, actions)
          : state.awaitingGood
          ? _awaitingGood(l, actions)
          : _running(l, state, actions),
      below: _logOpen ? _logPanel(l, t) : null,
    );
  }

  static const _hidden = SizedBox.shrink();

  /// The strip, with its children built against the width they have to fit
  /// into. [Wrap] offers every child unbounded width, so a child that has to
  /// ellipsize rather than overflow — the first bad commit's subject — can
  /// only learn its ceiling from the strip itself.
  ///
  /// [below] hangs under the row of controls, full width, for the one thing
  /// too tall to wrap alongside them: the verdict trail.
  Widget _wrap(
    AppTokens t,
    List<Widget> Function(double width) children, {
    Widget? below,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: t.bgElevated,
      border: Border(bottom: BorderSide(color: t.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children(c.maxWidth),
          ),
        ),
        if (below != null) ...[const SizedBox(height: 8), below],
      ],
    ),
  );

  /// How tall the trail may get before it scrolls instead of growing.
  ///
  /// The bar sits above the commit list and takes its height out of it, so an
  /// uncapped trail — a long hunt records a line per verdict, and git replays
  /// the whole session — would push the graph off the bottom of the window.
  static const _logMaxHeight = 160.0;

  /// The verdict trail, as git wrote it.
  ///
  /// Shown verbatim in a monospace face: it is a replayable script, and the
  /// point of having it is being able to copy it out somewhere it will be
  /// run or quoted. Nothing to show says so in words — a failed fetch and an
  /// empty trail are different facts, and an empty box states neither.
  Widget _logPanel(AppLocalizations l, AppTokens t) {
    final text = _log?.trim() ?? '';
    final nothing = _logFailed
        ? l.bisectLogFailed
        : text.isEmpty
        ? l.bisectLogEmpty
        : null;
    return Container(
      constraints: const BoxConstraints(maxHeight: _logMaxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.rCard),
      ),
      child: nothing != null
          ? Text(nothing, style: TextStyle(color: t.textMuted, fontSize: 12))
          : SingleChildScrollView(
              child: SelectableText(
                text,
                style: AppFonts.mns(size: 11.5, color: t.textPrimary),
              ),
            ),
    );
  }

  /// `git bisect start` was run but nothing has been marked yet: not
  /// awaiting-good (that needs a bad mark), not finished, and the vars git
  /// would use for counts were never computed. Reset is the only action
  /// that makes sense here — there is nothing to halve.
  List<Widget> _noMarks(AppLocalizations l, RepoActions actions) => [
    Text(l.bisectNoMarks),
    TextButton(onPressed: actions.resetBisect, child: Text(l.bisectReset)),
  ];

  /// A bad commit is marked but no good one is, so git has nothing to
  /// halve and offers no candidate range yet.
  List<Widget> _awaitingGood(AppLocalizations l, RepoActions actions) => [
    Text(l.bisectAwaitingGood),
    TextButton(onPressed: actions.resetBisect, child: Text(l.bisectReset)),
  ];

  List<Widget> _running(
    AppLocalizations l,
    BisectState state,
    RepoActions actions,
  ) {
    // Held so a click on Good cannot race git's own marking while a run
    // command is walking the range on its own.
    final runningCommand = ref.watch(bisectRunProvider(widget.repoPath));
    // Only meaningful once nothing is running: while one is, the row is
    // busy saying so, and a leftover explanation from an earlier attempt
    // would talk over it.
    final outcomeMessage = runningCommand == null
        ? _outcomeMessage(l, _lastRunOutcome)
        : null;
    return [
      // revisionsLeft/steps are -1 until git has both ends of the range; -1
      // is a sentinel for "not computed", never a count to show.
      if (state.revisionsLeft >= 0)
        Text(l.bisectRevisionsLeft(state.revisionsLeft)),
      if (state.steps >= 0) Text(l.bisectStepsLeft(state.steps)),
      Text(l.bisectTesting(_short(state.currentSha))),
      if (runningCommand != null)
        Text(l.bisectRunning(runningCommand))
      else ...[
        ElevatedButton(
          onPressed: () =>
              actions.markBisect(state.currentSha, BisectKind.good),
          child: Text(l.bisectGood),
        ),
        ElevatedButton(
          onPressed: () => actions.markBisect(state.currentSha, BisectKind.bad),
          child: Text(l.bisectBad),
        ),
        TextButton(onPressed: actions.skipBisect, child: Text(l.bisectSkip)),
        // Only offered here: this is the one state where git has both ends
        // of a range to hand a command, so only here can it iterate at all.
        TextButton(onPressed: () => _run(actions), child: Text(l.bisectRun)),
      ],
      _logToggle(l, actions),
      // Out of reach while a run is going: `git bisect reset` would put a
      // second git process on the same .git/BISECT_* state and throw away the
      // hunt the run is still adding to. Stopping a run is the status bar's
      // Cancel, and the "Running …" line beside this button says as much.
      TextButton(
        onPressed: runningCommand == null ? actions.resetBisect : null,
        child: Text(l.bisectReset),
      ),
      if (outcomeMessage != null) Text(outcomeMessage),
    ];
  }

  /// Shows and hides the verdict trail. Disabled only while a fetch is in
  /// flight, so a second press cannot stack a second read on the first.
  Widget _logToggle(AppLocalizations l, RepoActions actions) => TextButton(
    onPressed: _logBusy ? null : () => _toggleLog(actions),
    child: Text(l.bisectLog),
  );

  /// The commit the hunt landed on, as the graph already knows it, or null
  /// when it sits outside the page of history currently loaded.
  ///
  /// The graph pages its walk, and a bisect can end on a commit older than
  /// the page — nothing guarantees the answer is on screen. A miss is a
  /// normal outcome, not a failure: the card falls back to the sha, which is
  /// the one thing always known.
  Commit? _loadedCommit(String sha) {
    final commits = ref
        .watch(repoDataProvider(widget.repoPath))
        .valueOrNull
        ?.commits;
    if (commits == null) return null;
    for (final c in commits) {
      if (c.sha == sha) return c;
    }
    return null;
  }

  List<Widget> _finished(
    AppLocalizations l,
    AppTokens t,
    BisectState state,
    RepoActions actions,
    double width,
  ) {
    final firstBad = state.firstBad!;
    final commit = _loadedCommit(firstBad);
    return [
      _firstBadCard(l, t, firstBad, commit, width),
      ElevatedButton(
        onPressed: () => widget.onJumpToCommit(firstBad),
        child: Text(l.bisectJumpToCommit),
      ),
      _revertAction(l, actions, commit),
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: firstBad)),
        child: Text(l.bisectCopySha),
      ),
      // Offered only when the commit is loaded: a fixup names its target by
      // subject, and the sha the card always has is not one. Nothing here
      // would guess a subject, so the action stays away rather than put a
      // line on the clipboard git will later refuse to match.
      if (commit != null)
        TextButton(
          onPressed: () => Clipboard.setData(
            ClipboardData(text: _fixupLine(commit.message)),
          ),
          child: Text(l.bisectCopyFixup),
        ),
      _logToggle(l, actions),
      TextButton(onPressed: actions.resetBisect, child: Text(l.bisectReset)),
    ];
  }

  /// Undoing the commit the hunt just named, without the detour of jumping to
  /// the row and opening its context menu first.
  ///
  /// Routed through [replayCommit], the same call the graph's own menu makes,
  /// so a merge is asked which parent to keep rather than handed to git
  /// without the `-m` it demands.
  ///
  /// A culprit outside the loaded page has no parent list to ask about, so
  /// there is no way to tell a merge from a plain commit and no parents to
  /// offer if it is one. That is a disabled action with a reason, not a
  /// revert fired off in the hope git accepts it.
  Widget _revertAction(
    AppLocalizations l,
    RepoActions actions,
    Commit? commit,
  ) {
    if (commit == null) {
      return Tooltip(
        message: l.bisectRevertNotLoaded,
        child: TextButton(onPressed: null, child: Text(l.bisectRevertCommit)),
      );
    }
    return TextButton(
      onPressed: () => replayCommit(
        commit: commit,
        op: MainlineOp.revert,
        actions: actions,
        pick: () => showMainlineDialog(
          context,
          commit: commit,
          op: MainlineOp.revert,
          subjects: parentSubjects(
            commit,
            ref.read(repoDataProvider(widget.repoPath)).valueOrNull?.commits ??
                const <Commit>[],
          ),
        ),
      ),
      child: Text(l.bisectRevertCommit),
    );
  }

  /// The answer the whole feature exists to produce, given the weight to say
  /// so: the bad verdict's own colour from [bisectVerdictColor], so the card
  /// and the marked row in the graph read as one thing, and the commit named
  /// in words rather than left as a hex string.
  ///
  /// Capped at the strip's own width so a long subject ellipsizes instead of
  /// pushing the row off the side of a narrow window.
  Widget _firstBadCard(
    AppLocalizations l,
    AppTokens t,
    String sha,
    Commit? commit,
    double width,
  ) {
    final bad = bisectVerdictColor(BisectKind.bad, t);
    // Sha first, because it is the part that is always there; the author
    // joins it only when the commit is one the graph has loaded.
    final meta = [
      _short(sha),
      if (commit != null && commit.author.isNotEmpty) commit.author,
    ].join('  ·  ');
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: bad.withValues(alpha: 0.12),
          border: Border.all(color: bad.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(t.rCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_problem_outlined, size: 17, color: bad),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.bisectFirstBadTitle,
                    style: TextStyle(
                      color: bad,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (commit != null)
                    Text(
                      commit.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// The `fixup!` line that marks a commit as amending [message]'s commit.
///
/// Git pairs a fixup with its target by matching the text after the marker
/// against the target's subject, so only the first line may travel: a second
/// line belongs to the body, and carrying it would leave an autosquash with
/// nothing to match.
String _fixupLine(String message) =>
    'fixup! ${message.split('\n').first.trim()}';

/// What to do about the detached HEAD a bisect leaves behind, offered in
/// place of a plain quit/close confirmation.
enum BisectQuitChoice { reset, quitAnyway, cancel }

/// Asked instead of the normal quit/close prompt while [BisectBar]'s guard
/// is registered — a bisect running or finished but not yet reset, either
/// way sitting on a detached HEAD.
Future<BisectQuitChoice> showBisectQuitDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final result = await showAppModal<BisectQuitChoice>(
    context: context,
    title: l.bisectQuitTitle,
    icon: Icons.warning_amber_rounded,
    width: 460,
    body: Builder(
      builder: (ctx) => Text(
        l.bisectQuitBody,
        style: TextStyle(
          color: ctx.tokens.textMuted,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(BisectQuitChoice.cancel),
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(BisectQuitChoice.quitAnyway),
          child: Text(l.bisectQuitAnyway),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(BisectQuitChoice.reset),
          child: Text(l.bisectReset),
        ),
      ),
    ],
  );
  // Dismissing the barrier is a decision not to leave silently: same as
  // cancel.
  return result ?? BisectQuitChoice.cancel;
}
