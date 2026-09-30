import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/lfs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';
import 'forge_presentation.dart';

/// Lock, unlock or force-unlock entries for a file's context menu. Empty
/// unless the file is LFS-managed and the server can lock, for a submodule,
/// and for a path starting with `-`, which git-lfs would read as an option.
List<PopupMenuEntry<void>> lfsLockMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required String repoPath,
  required String path,
  required bool isLfs,
  bool submodule = false,
}) {
  if (!isLfs || submodule || path.startsWith('-')) return const [];
  final state = ref.read(lfsLocksProvider(repoPath)).valueOrNull;
  if (state == null || !state.available) return const [];
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));
  final lock = state.lockFor(path);

  PopupMenuItem<void> item(String label, VoidCallback onTap) => PopupMenuItem(
    height: 34,
    onTap: onTap,
    child: Text(label, style: const TextStyle(fontSize: 13)),
  );

  final LfsLock? held = lock;
  final ours = state.isOurs(path);
  return [
    const PopupMenuDivider(height: 1),
    if (held == null)
      item(l.lfsLockFile, () => actions.lfsLock(path))
    else if (ours)
      item(l.lfsUnlockFile, () => actions.lfsUnlock(held))
    else
      item(
        l.lfsForceUnlock,
        () => confirmLfsForceUnlock(context, ref, repoPath, held),
      ),
  ];
}

/// Asks before breaking someone else's lock, and breaks it only on a yes.
Future<void> confirmLfsForceUnlock(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
  LfsLock lock,
) async {
  final l = AppLocalizations.of(context);
  // Taken before the dialog: the row that raised it may be gone by then.
  final actions = ref.read(repoActionsProvider(repoPath));
  final ok = await confirmDestructive(
    ref,
    context,
    title: l.lfsForceUnlockTitle,
    body: switch (forgeAgo(l, lock.lockedAt)) {
      null => l.lfsForceUnlockBodyNoAge(lock.owner),
      final age => l.lfsForceUnlockBody(lock.owner, age),
    },
    confirmLabel: l.lfsForceUnlockConfirm,
  );
  // No mounted check: the confirmed unlock needs nothing from the row.
  if (!ok) return;
  await actions.lfsForceUnlock(lock);
}
