import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';

/// Says how many LFS-managed files in the working tree are still pointers
/// and offers to bring their content down. Goes away by itself once they
/// are downloaded; there is nothing to dismiss.
class LfsPointerStrip extends ConsumerWidget {
  final String repoPath;
  final List<WorkingFile> working;
  const LfsPointerStrip({
    super.key,
    required this.repoPath,
    required this.working,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pointers =
        ref
            .watch(
              lfsPointerFilesProvider(workingTreeLfsSource(repoPath, working)),
            )
            .valueOrNull ??
        const <String>{};
    if (pointers.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Container(
      color: t.bgElevated,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.lfsPointerStrip(pointers.length),
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(repoActionsProvider(repoPath)).lfsPull(),
            child: Text(l.lfsDownload, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
