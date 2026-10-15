import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../../state/shallow.dart';

/// A pill that marks a shallow clone, so missing history is never a surprise.
/// Clicking it fetches the rest of the history; once that lands the pill goes.
class ShallowBadge extends ConsumerWidget {
  final String path;
  const ShallowBadge({super.key, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shallow = ref.watch(shallowRepoProvider(path)).valueOrNull ?? false;
    if (!shallow) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Tooltip(
      message: l.cloShallowTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          await ref.read(repoActionsProvider(path)).fetchFullHistory();
          // A deepening fetch need not move any ref, so the refs-driven
          // re-read may never come; ask again directly.
          ref.invalidate(shallowRepoProvider(path));
        },
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: t.warning.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l.cloShallowBadge.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.warning,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
