import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/dialogs.dart';
import '../diff/lfs_card.dart';

/// Checks, before a push, that LFS objects would go up with the commits.
/// Asks the user only when they would not; returns whether to push.
Future<bool> confirmLfsPushReady(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final working =
      ref.read(repoDataProvider(repoPath)).valueOrNull?.working ??
      const <WorkingFile>[];
  final readiness = await ref.read(
    lfsPushReadinessProvider(workingTreeLfsSource(repoPath, working)).future,
  );
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
      return ref.read(repoActionsProvider(repoPath)).lfsInstallHooks();
    case _Choice.pushAnyway:
      return true;
    case _Choice.cancel || null:
      return false;
  }
}

enum _Choice { install, pushAnyway, cancel }
