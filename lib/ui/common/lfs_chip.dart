import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';

/// Marks a file whose content lives in Git LFS rather than in the repository.
class LfsChip extends StatelessWidget {
  const LfsChip({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.lfsBadgeTooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          l.lfsBadge,
          style: TextStyle(
            color: t.accent,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
