import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/graph_ref_filter.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_ref_filter.dart';

/// Says the graph is narrowed — branches hidden or soloed — with a way to
/// show everything again. Without it, missing commits would read as missing
/// history. Renders nothing when no branch is hidden or soloed.
class GraphRefFilterBar extends ConsumerWidget {
  final String repoPath;
  const GraphRefFilterBar({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(graphRefFilterProvider(repoPath)).valueOrNull;
    if (f == null || f.isEmpty) return const SizedBox.shrink();
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
