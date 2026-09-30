import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_writer.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/dialogs.dart';
import '../diff/lfs_card.dart';

/// Checks, before a push, that LFS objects would go up with the commits, then
/// that no file others have locked is among them. Asks the user only when a
/// check fails; returns whether to push. Pass [tag] when pushing that tag
/// rather than the current branch.
Future<bool> confirmLfsPushReady(
  BuildContext context,
  WidgetRef ref,
  String repoPath, {
  String? tag,
}) async {
  if (!await _confirmObjectsReady(context, ref, repoPath)) return false;
  if (!context.mounted) return true;
  return _confirmNoLockedFiles(context, ref, repoPath, tag);
}

/// Warns when the push carries changes to files others hold locks on.
///
/// Reads the lock list as it stands and never waits for it or refreshes it: a
/// push must not wait on the lock server. No list yet, or no locking, skips.
Future<bool> _confirmNoLockedFiles(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
  String? tag,
) async {
  final locks = ref.read(lfsLocksProvider(repoPath)).valueOrNull;
  if (locks == null || !locks.available || locks.theirs.isEmpty) return true;
  final branches =
      ref.read(repoDataProvider(repoPath)).valueOrNull?.branches ??
      const <Branch>[];
  final upstream = branches.where((b) => b.current).firstOrNull?.upstream;
  final writer = GitWriter(ref.read(gitServiceProvider), repoPath);
  final List<String> changed;
  try {
    changed = await writer.changedPathsToPush(
      upstream: upstream,
      rev: tag == null ? 'HEAD' : 'refs/tags/$tag',
    );
  } on Object {
    return true;
  }
  final changedSet = changed.toSet();
  final hits = [
    for (final lock in locks.theirs)
      if (changedSet.contains(lock.path)) lock,
  ];
  if (hits.isEmpty || !context.mounted) return true;
  final l = AppLocalizations.of(context);
  final t = context.tokens;
  const shown = 10;
  final ok = await showAppModal<bool>(
    context: context,
    title: l.lfsPushLockedTitle,
    icon: Icons.lock_outline,
    width: 480,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.lfsPushLockedBody,
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        for (final lock in hits.take(shown))
          Text(
            '${lock.path} — ${lock.owner}',
            style: TextStyle(color: t.textPrimary, fontSize: 12.5, height: 1.5),
          ),
        if (hits.length > shown)
          Text(
            l.lfsLocksMore(hits.length - shown),
            style: TextStyle(color: t.textMuted, fontSize: 12.5, height: 1.5),
          ),
      ],
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.lfsPushAnyway),
        ),
      ),
    ],
  );
  return ok ?? false;
}

Future<bool> _confirmObjectsReady(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final working =
      ref.read(repoDataProvider(repoPath)).valueOrNull?.working ??
      const <WorkingFile>[];
  final source = workingTreeLfsSource(repoPath, working);
  final readiness = await ref.read(lfsPushReadinessProvider(source).future);
  if (readiness == LfsPushReadiness.ready || !context.mounted) {
    return readiness == LfsPushReadiness.ready;
  }
  final l = AppLocalizations.of(context);
  final hookMissing = readiness == LfsPushReadiness.hookMissing;
  final t = context.tokens;
  Widget button(_Choice value, String label, {bool primary = false}) => Builder(
    builder: (ctx) => primary
        ? FilledButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: Text(label),
          )
        : TextButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: Text(label),
          ),
  );
  final choice = await showAppModal<_Choice>(
    context: context,
    title: hookMissing ? l.lfsPushHookTitle : l.lfsPushToolTitle,
    icon: Icons.warning_amber_rounded,
    width: 480,
    body: Text(
      hookMissing
          ? l.lfsPushHookBody
          : '${l.lfsPushToolBody}\n\n'
                '${lfsInstallHint(l, lfsInstallRoute(lfsOperatingSystem(context)))}',
      style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
    ),
    actions: [
      button(_Choice.cancel, l.cancel),
      button(_Choice.pushAnyway, l.lfsPushAnyway),
      if (hookMissing)
        button(_Choice.install, l.lfsPushInstallAndPush, primary: true),
    ],
  );
  switch (choice) {
    case _Choice.install:
      final toasts = ref.read(toastProvider.notifier);
      if (!await ref.read(repoActionsProvider(repoPath)).lfsInstallHooks()) {
        return false;
      }
      // git-lfs reports success yet leaves an existing pre-push hook that
      // lacks the execute bit untouched, and git skips such a hook. Look
      // again rather than trusting the exit code; the file is the user's, so
      // its mode is theirs to change.
      final after = await ref.refresh(lfsPushReadinessProvider(source).future);
      if (after == LfsPushReadiness.ready) return true;
      toasts.show(l.lfsPushHookNotRunnable, kind: ToastKind.error);
      return false;
    case _Choice.pushAnyway:
      return true;
    case _Choice.cancel || null:
      return false;
  }
}

enum _Choice { install, pushAnyway, cancel }
