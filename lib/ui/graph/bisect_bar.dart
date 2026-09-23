import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/bisect.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/bisect.dart';
import '../../state/repo_actions.dart';

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
class BisectBar extends ConsumerWidget {
  final String repoPath;
  final void Function(String sha) onJumpToCommit;

  const BisectBar({
    super.key,
    required this.repoPath,
    required this.onJumpToCommit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bisectStateProvider(repoPath)).valueOrNull;
    if (state == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final actions = ref.read(repoActionsProvider(repoPath));
    final t = context.tokens;

    final hasBad = state.marks.any((m) => m.kind == BisectKind.bad);
    final children = state.finished
        ? _finished(l, state, actions)
        // No bad mark yet: git has nothing to halve, whether that's because
        // no marks exist at all or only good ones were typed at a terminal
        // before a bad one. Both read the same to the person using the bar.
        : !hasBad
        ? _noMarks(l, actions)
        : state.awaitingGood
        ? _awaitingGood(l, actions)
        : _running(l, state, actions);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
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
  ) => [
    // revisionsLeft/steps are -1 until git has both ends of the range; -1
    // is a sentinel for "not computed", never a count to show.
    if (state.revisionsLeft >= 0)
      Text(l.bisectRevisionsLeft(state.revisionsLeft)),
    if (state.steps >= 0) Text(l.bisectStepsLeft(state.steps)),
    Text(l.bisectTesting(_short(state.currentSha))),
    ElevatedButton(
      onPressed: () => actions.markBisect(state.currentSha, BisectKind.good),
      child: Text(l.bisectGood),
    ),
    ElevatedButton(
      onPressed: () => actions.markBisect(state.currentSha, BisectKind.bad),
      child: Text(l.bisectBad),
    ),
    TextButton(onPressed: actions.skipBisect, child: Text(l.bisectSkip)),
    TextButton(onPressed: actions.resetBisect, child: Text(l.bisectReset)),
  ];

  List<Widget> _finished(
    AppLocalizations l,
    BisectState state,
    RepoActions actions,
  ) {
    final firstBad = state.firstBad!;
    return [
      Text(l.bisectFirstBadTitle),
      Text(_short(firstBad)),
      TextButton(
        onPressed: () => onJumpToCommit(firstBad),
        child: Text(l.bisectJumpToCommit),
      ),
      TextButton(
        onPressed: () => Clipboard.setData(ClipboardData(text: firstBad)),
        child: Text(l.bisectCopySha),
      ),
      TextButton(onPressed: actions.resetBisect, child: Text(l.bisectReset)),
    ];
  }

  String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;
}
