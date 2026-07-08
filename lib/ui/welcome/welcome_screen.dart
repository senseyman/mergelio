import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/recents.dart';
import '../common/dialogs.dart';
import 'open_repo.dart';
import 'repo_dialogs.dart';

/// Shown when no repository is open. Hero + three actions + recents list.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final recents = ref.watch(recentsProvider);

    return Container(
      color: t.bgApp,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Actions
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to Mergelio',
                      style: AppFonts.disp(size: 30, color: t.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Free visual Git client. Get started:',
                      style: TextStyle(color: t.textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    _ActionCard(
                      icon: Icons.cloud_download_outlined,
                      title: 'Clone repository',
                      subtitle: 'From a URL (HTTPS/SSH) into a folder',
                      onTap: () => showCloneDialog(context),
                    ),
                    _ActionCard(
                      icon: Icons.add_box_outlined,
                      title: 'Create repository',
                      subtitle: 'New local repository with README/.gitignore',
                      onTap: () => showCreateDialog(context),
                    ),
                    _ActionCard(
                      icon: Icons.folder_open_outlined,
                      title: 'Open repository',
                      subtitle: 'Choose an existing folder with .git',
                      onTap: () => openRepositoryFlow(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              // Recents
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        l.welcomeRecents.toUpperCase(),
                        style: TextStyle(
                          color: t.textFaint,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (recents.isEmpty)
                      Text(
                        l.welcomeNoRecents,
                        style: TextStyle(color: t.textFaint, fontSize: 13),
                      )
                    else
                      for (final r in recents) _RecentRow(repo: r),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.bgPanel,
        borderRadius: BorderRadius.circular(t.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.rCard),
          hoverColor: t.hover,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.rCard),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.active,
                    borderRadius: BorderRadius.circular(t.rButton),
                  ),
                  child: Icon(icon, size: 20, color: t.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: t.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends ConsumerWidget {
  final RecentRepo repo;
  const _RecentRow({required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return GestureDetector(
      onSecondaryTapDown: (d) async {
        final action = await showContextMenu<String>(
          context: context,
          position: d.globalPosition,
          items: [
            PopupMenuItem(
              value: 'pin',
              height: 36,
              child: Text(repo.pinned ? 'Unpin' : 'Pin'),
            ),
            const PopupMenuItem(
              value: 'remove',
              height: 36,
              child: Text('Remove from recents'),
            ),
          ],
        );
        final ctl = ref.read(recentsProvider.notifier);
        switch (action) {
          case 'pin':
            ctl.togglePin(repo.path);
          case 'remove':
            ctl.remove(repo.path);
        }
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(t.rButton),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.rButton),
          hoverColor: t.hover,
          onTap: () => openRepositoryPath(ref, repo.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 17, color: t.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.name,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        repo.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.mns(size: 11, color: t.textFaint),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  tooltip: repo.pinned ? 'Unpin' : 'Pin',
                  icon: Icon(
                    repo.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: repo.pinned ? t.accent : t.textFaint,
                  ),
                  onPressed: () =>
                      ref.read(recentsProvider.notifier).togglePin(repo.path),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
