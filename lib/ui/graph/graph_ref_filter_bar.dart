import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/graph_ref_filter.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_ref_filter.dart';
import '../../state/repo_data.dart';

/// Says the graph is narrowed — branches hidden or soloed — with a way to
/// show everything again. Without it, missing commits would read as missing
/// history. Renders nothing when no branch is hidden or soloed.
class GraphRefFilterBar extends ConsumerWidget {
  final String repoPath;

  /// The graph's own data, for which refs exist and which branch is checked
  /// out. Passed in rather than watched, so the bar starts no load of its own.
  final RepoData data;
  const GraphRefFilterBar({
    super.key,
    required this.repoPath,
    required this.data,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(graphRefFilterProvider(repoPath)).valueOrNull;
    if (saved == null || saved.isEmpty) {
      return const SizedBox.shrink();
    }
    // What the graph is applying, not what was saved: a branch deleted or
    // checked out since must not be reported as narrowing the graph.
    final f = saved.effective(
      live: {
        for (final b in data.branches) 'refs/heads/${b.name}',
        for (final rb in data.remoteBranches)
          'refs/remotes/${rb.remote}/${rb.branch}',
      },
      current: data.branches.where((b) => b.current).firstOrNull?.name,
    );
    if (f.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final label = f.solo.isNotEmpty
        ? l.grfBarSolo((f.solo.map(shortRefName).toList()..sort()).join(', '))
        : l.grfBarHidden(f.hidden.length);
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
          Icon(
            f.solo.isNotEmpty
                ? Icons.filter_center_focus
                : Icons.visibility_off,
            size: 14,
            color: t.textMuted,
          ),
          Text(label, style: TextStyle(color: t.textPrimary, fontSize: 12)),
          TextButton(
            onPressed: () =>
                ref.read(graphRefFilterProvider(repoPath).notifier).clear(),
            child: Text(l.grfShowAll),
          ),
        ],
      ),
    );
  }
}
