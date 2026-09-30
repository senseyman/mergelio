import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/lfs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../workspace/forge_presentation.dart';

/// Marks a file locked on the LFS server: "You" for the user's own lock, the
/// owner's name for someone else's.
class LfsLockChip extends StatelessWidget {
  const LfsLockChip({super.key, required this.lock, required this.ours});

  final LfsLock lock;
  final bool ours;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final color = ours ? t.textMuted : t.warning;
    return Tooltip(
      message: lfsLockTooltip(l, lock),
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 10, color: color),
            const SizedBox(width: 2),
            // A long owner name must not push the row's path out of view.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                ours ? l.lfsLockChipYou : lock.owner,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lock chip tooltip, without the age when the server gave no time.
String lfsLockTooltip(AppLocalizations l, LfsLock lock) {
  final age = forgeAgo(l, lock.lockedAt);
  return age == null
      ? l.lfsLockTooltipNoAge(lock.owner)
      : l.lfsLockTooltip(lock.owner, age);
}
