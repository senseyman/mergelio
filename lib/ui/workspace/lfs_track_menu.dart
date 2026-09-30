import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/lfs.dart';
import '../../state/repo_actions.dart';
import '../common/dialogs.dart';

const _maxListed = 20;

/// The LFS entries of a working-tree file's context menu. Empty when git-lfs
/// is missing, for a submodule, and for a path starting with `-` (which git-lfs
/// would read as an option). Tracking needs only the tool, not an LFS-using
/// repository, so it is offered everywhere else.
List<PopupMenuEntry<void>> lfsTrackMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required String repoPath,
  required WorkingFile file,
  required bool isLfs,
}) {
  if (ref.read(lfsToolProvider).valueOrNull == null) return const [];
  if (file.submodule || file.path.startsWith('-')) return const [];
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));
  final ext = lfsExtensionPattern(file.path);

  Future<void> track(Future<bool> Function() run) async {
    if (await run() && context.mounted) {
      await offerLfsConvert(context, ref, repoPath);
    }
  }

  PopupMenuItem<void> item(String label, VoidCallback onTap) => PopupMenuItem(
    height: 34,
    onTap: onTap,
    child: Text(label, style: const TextStyle(fontSize: 13)),
  );

  return [
    const PopupMenuDivider(height: 1),
    if (ext != null)
      item(l.lfsTrackExtension(ext), () => track(() => actions.lfsTrack(ext))),
    item(l.lfsTrackFile, () => track(() => actions.lfsTrackFile(file.path))),
    if (isLfs)
      item(l.lfsUntrack, () => showLfsUntrackDialog(context, ref, repoPath)),
  ];
}

/// Lists the tracked patterns and untracks the one the user picks.
Future<void> showLfsUntrackDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));
  final toasts = ref.read(toastProvider.notifier);
  final List<LfsTrackedPattern> patterns;
  try {
    patterns = [
      for (final p in await actions.lfsTrackedPatterns())
        // A pattern shaped like an option would be parsed as one.
        if (!p.pattern.startsWith('-')) p,
    ];
  } on Object catch (e) {
    toasts.show(l.lfsUntrackTitle, description: '$e', kind: ToastKind.error);
    return;
  }
  if (!context.mounted) return;
  final picked = await showAppModal<String>(
    context: context,
    title: l.lfsUntrackTitle,
    icon: Icons.link_off,
    width: 460,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.lfsUntrackBody),
        const SizedBox(height: 12),
        for (final p in patterns)
          Builder(
            builder: (ctx) => InkWell(
              onTap: () => Navigator.of(ctx).pop(p.pattern),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${p.pattern} (${p.source})',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppFonts.mono,
                    fontFamilyFallback: AppFonts.monoFallback,
                    color: ctx.tokens.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  if (picked != null) await actions.lfsUntrack(picked);
}

/// After a pattern change, offers to re-stage the committed files it now
/// reaches. Says nothing when there are none.
Future<void> offerLfsConvert(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  final actions = ref.read(repoActionsProvider(repoPath));
  final toasts = ref.read(toastProvider.notifier);
  final List<String> candidates;
  try {
    candidates = await actions.lfsConvertCandidates();
  } on Object catch (e) {
    toasts.show(l.lfsConvertTitle, description: '$e', kind: ToastKind.error);
    return;
  }
  if (candidates.isEmpty) return;
  toasts.show(
    l.lfsConvertOffer(candidates.length),
    kind: ToastKind.info,
    action: ToastAction(
      l.lfsConvertAction,
      () => _showConvertDialog(context, ref, repoPath, candidates),
    ),
  );
}

Future<void> _showConvertDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
  List<String> candidates,
) async {
  // The toast can outlive the widget that raised it.
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  // Taken now: the row that raised the toast may be gone once the dialog
  // closes, and with it the ref.
  final actions = ref.read(repoActionsProvider(repoPath));
  final shown = candidates.take(_maxListed).toList();
  final rest = candidates.length - shown.length;
  final ok = await showAppModal<bool>(
    context: context,
    title: l.lfsConvertTitle,
    icon: Icons.swap_horiz,
    width: 480,
    body: Builder(
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.lfsConvertBody),
          const SizedBox(height: 12),
          for (final f in shown)
            Text(
              f,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallback,
                color: ctx.tokens.textMuted,
              ),
            ),
          if (rest > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.lfsConvertMore(rest),
                style: TextStyle(fontSize: 12.5, color: ctx.tokens.textFaint),
              ),
            ),
        ],
      ),
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
          child: Text(l.lfsConvertConfirm),
        ),
      ),
    ],
  );
  if (ok == true) {
    await actions.lfsConvert(candidates);
  }
}
