import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/feedback.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';
import 'forge_presentation.dart';
import 'lfs_lock_menu.dart';

const _maxRows = 100;

/// The server's page size for a lock query; a full page means more may exist.
const _queryLimit = 1000;

/// Who holds file locks in this repository: the user's own first, then
/// everyone else's. Absent while locking is unavailable.
class LfsLocksSection extends ConsumerWidget {
  const LfsLocksSection({
    super.key,
    required this.repoPath,
    this.working = const [],
  });

  final String repoPath;

  /// Changed files; a row opens its diff when its path is among them.
  final List<WorkingFile> working;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(lfsLocksProvider(repoPath));
    final state = async.valueOrNull;
    if (state == null || !state.available) return const SizedBox.shrink();
    final t = context.tokens;

    final total = state.ours.length + state.theirs.length;
    final ours = state.ours.take(_maxRows).toList();
    final theirs = state.theirs.take(_maxRows - ours.length).toList();
    final hidden = total - ours.length - theirs.length;

    return Container(
      color: t.bgElevated,
      constraints: const BoxConstraints(maxHeight: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.lfsLocksSection,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (async.isLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                IconButton(
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  tooltip: switch (forgeAgo(l, state.refreshedAt)) {
                    null => l.lfsLocksRefresh,
                    final age =>
                      '${l.lfsLocksRefresh} · ${l.lfsLocksRefreshedAt(age)}',
                  },
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref
                      .read(lfsGenerationProvider(repoPath).notifier)
                      .state++,
                ),
              ],
            ),
          ),
          if (state.stale)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                l.lfsLocksStale,
                style: TextStyle(color: t.warning, fontSize: 11.5),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ours.isNotEmpty) _GroupLabel(l.lfsLocksYours),
                  for (final lock in ours)
                    _LockRow(
                      lock: lock,
                      repoPath: repoPath,
                      working: working,
                      ours: true,
                    ),
                  if (theirs.isNotEmpty) _GroupLabel(l.lfsLocksOthers),
                  for (final lock in theirs)
                    _LockRow(
                      lock: lock,
                      repoPath: repoPath,
                      working: working,
                      ours: false,
                    ),
                  if (hidden > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Text(
                        // A full page from the server means the true count is
                        // unknown, so the hidden figure is a floor.
                        total >= _queryLimit
                            ? l.lfsLocksMoreAtLeast(hidden)
                            : l.lfsLocksMore(hidden),
                        style: TextStyle(color: t.textFaint, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says once, when it is found out, that the server cannot lock files. Wraps
/// the whole workspace: the lock query also runs under commit details and
/// compare, where no locks section is mounted to say it.
class LfsLocksUnsupportedNotice extends ConsumerWidget {
  const LfsLocksUnsupportedNotice({
    super.key,
    required this.repoPath,
    required this.child,
  });

  final String repoPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(lfsLocksUnsupportedProvider(repoPath), (prev, next) {
      if (next && prev != true) {
        ref
            .read(toastProvider.notifier)
            .show(
              AppLocalizations.of(context).lfsLocksUnsupported,
              kind: ToastKind.info,
            );
      }
    });
    return child;
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
    child: Text(
      label,
      style: TextStyle(
        color: context.tokens.textFaint,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _LockRow extends ConsumerWidget {
  const _LockRow({
    required this.lock,
    required this.repoPath,
    required this.working,
    required this.ours,
  });

  final LfsLock lock;
  final String repoPath;
  final List<WorkingFile> working;
  final bool ours;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final age = forgeAgo(l, lock.lockedAt);
    final changed = working.where((f) => f.path == lock.path).firstOrNull;
    return InkWell(
      onTap: changed == null
          ? null
          : () => ref.read(diffTargetProvider.notifier).state = DiffTarget(
              repoPath: repoPath,
              path: lock.path,
              staged: !changed.isUnstaged,
            ),
      hoverColor: t.hover,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lock.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12,
                      fontFamily: AppFonts.mono,
                      fontFamilyFallback: AppFonts.monoFallback,
                    ),
                  ),
                  Text(
                    age == null ? lock.owner : '${lock.owner} · $age',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => ours
                  ? ref.read(repoActionsProvider(repoPath)).lfsUnlock(lock)
                  : confirmLfsForceUnlock(context, ref, repoPath, lock),
              child: Text(
                ours ? l.lfsUnlockFile : l.lfsForceUnlock,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
