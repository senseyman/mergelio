import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';

/// Strip above the commit list while two or more commits are picked with
/// Cmd/Ctrl- or Shift-click: how many, and what can be done with them.
///
/// Laid out with [Wrap] rather than [Row] for the same reason as the bisect
/// bar: the graph panel can be as narrow as 336px, well short of the three
/// buttons and the count side by side.
class PickBar extends ConsumerWidget {
  final String repoPath;

  /// The graph's commits, newest first, as the list shows them.
  final List<Commit> commits;

  const PickBar({super.key, required this.repoPath, required this.commits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(commitPicksProvider(repoPath));
    final count = picks.isEmpty
        ? 0
        : picks.oldestFirst([for (final c in commits) c.sha]).length;
    if (count < 2) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
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
        children: [
          Text(
            l.pickSelected(count),
            style: TextStyle(color: t.textPrimary, fontSize: 12),
          ),
          TextButton(
            onPressed: () => cherryPickPicks(ref, l, repoPath, commits),
            child: Text(l.pickCherryPick),
          ),
          TextButton(
            onPressed: () =>
                cherryPickPicks(ref, l, repoPath, commits, noCommit: true),
            child: Text(l.pickNoCommit),
          ),
          TextButton(
            onPressed: () =>
                ref.read(commitPicksProvider(repoPath).notifier).state =
                    CommitPicks.none,
            child: Text(l.pickClear),
          ),
        ],
      ),
    );
  }
}

/// Cherry-picks the commits picked in [repoPath]'s graph, oldest first
/// whatever order they were clicked in. [commits] is the graph, newest first.
/// The picks clear once the batch has run; when it changed nothing — a merge
/// among them, an unfinished pick in the way — they stay, so the user can fix
/// what was wrong and go again.
Future<void> cherryPickPicks(
  WidgetRef ref,
  AppLocalizations l,
  String repoPath,
  List<Commit> commits, {
  bool noCommit = false,
}) async {
  final picks = ref.read(commitPicksProvider(repoPath).notifier);
  final shas = picks.state.oldestFirst([for (final c in commits) c.sha]);
  if (shas.isEmpty) return;
  final bySha = {for (final c in commits) c.sha: c};
  final merge = firstMergeOf([for (final s in shas) bySha[s]!]);
  if (merge != null) {
    ref
        .read(toastProvider.notifier)
        .show(
          l.pickMergeTitle,
          description: l.pickMergeBody(merge.shortSha),
          kind: ToastKind.warning,
        );
    return;
  }
  final ran = await ref
      .read(repoActionsProvider(repoPath))
      .cherryPickMany(shas, noCommit: noCommit);
  if (ran) picks.state = CommitPicks.none;
}
