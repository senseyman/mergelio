import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/lfs.dart';
import '../diff/lfs_card.dart';

/// Says once, for the whole repository, why its large files read as small
/// text files: they are LFS pointers and nothing on this machine can swap in
/// the content. Better than every diff looking like data loss.
class LfsBanner extends ConsumerWidget {
  final String repoPath;
  final List<WorkingFile> working;
  const LfsBanner({super.key, required this.repoPath, required this.working});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(
      lfsBannerDismissedProvider.select((s) => s.contains(repoPath)),
    );
    if (dismissed) return const SizedBox.shrink();
    final usesLfs =
        ref
            .watch(
              lfsRepoProvider(
                LfsSource(
                  repoPath: repoPath,
                  attrsStamp: lfsAttrsStamp(working),
                ),
              ),
            )
            .valueOrNull ??
        false;
    final tool = ref.watch(lfsToolProvider);
    // Only a settled "not installed" counts; a probe still running says
    // nothing yet.
    if (!usesLfs || !tool.hasValue || tool.value != null) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final os = lfsOperatingSystem(context);
    return Container(
      color: t.bgElevated,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.lfsBannerText,
                  style: TextStyle(color: t.textPrimary, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  lfsInstallHint(l, lfsInstallRoute(os)),
                  style: TextStyle(color: t.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(lfsBannerDismissedProvider.notifier)
                .update((s) => {...s, repoPath}),
            child: Text(
              l.lfsBannerDismiss,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
