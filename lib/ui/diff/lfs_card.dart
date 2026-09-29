import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/diff.dart';
import '../../domain/git/lfs.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_document.dart';
import '../../state/diff_target.dart';
import '../../state/lfs.dart';
import '../../state/repo_data.dart';

/// The usual way to get git-lfs on [route]'s platform, as one sentence.
String lfsInstallHint(AppLocalizations l, LfsInstallRoute route) =>
    switch (route) {
      LfsInstallRoute.homebrew => l.lfsInstallHomebrew,
      LfsInstallRoute.gitForWindows => l.lfsInstallGitForWindows,
      LfsInstallRoute.packageManager => l.lfsInstallPackageManager,
    };

/// Stands in for a diff whose sides are LFS pointers: three lines of pointer
/// text read like the file was emptied, so this says what actually changed.
class LfsCard extends ConsumerWidget {
  final String repoPath;
  final FileDiff file;

  /// Offered when one side is ordinary text, whose diff is still worth
  /// reading.
  final VoidCallback? onShowText;

  const LfsCard({
    super.key,
    required this.repoPath,
    required this.file,
    this.onShowText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final lfs = file.lfs!;
    final kind = lfsChangeKind(file);
    final title = switch (kind) {
      LfsChangeKind.modified => l.lfsCardModified,
      LfsChangeKind.added => l.lfsCardAdded,
      LfsChangeKind.deleted => l.lfsCardDeleted,
      LfsChangeKind.movedIn => l.lfsCardMovedIn,
      LfsChangeKind.movedOut => l.lfsCardMovedOut,
    };
    final sizes = [
      if (lfs.before != null) formatLfsSize(lfs.before!.size),
      if (lfs.after != null) formatLfsSize(lfs.after!.size),
    ].join(' → ');
    // Only a settled "not installed" counts; a probe still running says
    // nothing yet.
    final tool = ref.watch(lfsToolProvider);
    final toolMissing = tool.hasValue && tool.value == null;
    final muted = TextStyle(color: t.textMuted, fontSize: 12);

    Widget side(LfsPointer p) {
      final present =
          ref
              .watch(lfsObjectPresentProvider((repoPath: repoPath, oid: p.oid)))
              .valueOrNull ??
          false;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.oid.substring(0, 12), style: muted),
          Text(' · ', style: muted),
          Text(present ? l.lfsDownloaded : l.lfsNotDownloaded, style: muted),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(sizes, style: TextStyle(color: t.textPrimary, fontSize: 12)),
            const SizedBox(height: 6),
            if (lfs.before != null) side(lfs.before!),
            if (lfs.after != null) side(lfs.after!),
            if (toolMissing) ...[
              const SizedBox(height: 8),
              Text(l.lfsToolMissing, style: muted),
              Text(
                lfsInstallHint(l, lfsInstallRoute(lfsOperatingSystem(context))),
                style: TextStyle(color: t.textFaint, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
            if (onShowText != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onShowText, child: Text(l.lfsShowTextDiff)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The platform whose install route to name. Read from the theme's platform,
/// so a widget test can pick one; on a real desktop both agree.
String lfsOperatingSystem(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      _ => Platform.operatingSystem,
    };

/// A file LFS should be managing that was committed as a regular blob — the
/// usual sign it was added on a machine without git-lfs. Worth seeing, since
/// every clone now carries the full content in history.
class LfsMismatchNote extends ConsumerWidget {
  final DiffTarget target;
  const LfsMismatchNote({super.key, required this.target});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(diffDocumentProvider(target)).valueOrNull;
    if (doc == null || doc.files.isEmpty || doc.isBinary) {
      return const SizedBox.shrink();
    }
    if (doc.files.any((f) => f.lfs != null)) return const SizedBox.shrink();
    final working = target.isWorkingTree
        ? ref.watch(repoDataProvider(target.repoPath)).valueOrNull?.working ??
              const <WorkingFile>[]
        : const <WorkingFile>[];
    // An untracked file is diffed against nothing, outside git's filters, so
    // its content always shows plain: that says nothing about how it would
    // be stored once added.
    if (working.any((f) => f.path == target.path && f.isUntracked)) {
      return const SizedBox.shrink();
    }
    final tracked =
        ref
            .watch(
              lfsPathsProvider(
                LfsQuery(lfsSourceFor(target, working: working), [target.path]),
              ),
            )
            .valueOrNull ??
        const <String>{};
    if (!tracked.contains(target.path)) return const SizedBox.shrink();
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        AppLocalizations.of(context).lfsMismatch,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.warning, fontSize: 11),
      ),
    );
  }
}
