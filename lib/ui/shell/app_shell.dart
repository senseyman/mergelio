import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auto_fetch.dart';
import '../../state/feedback.dart';
import '../../state/open_files_sync.dart';
import '../../state/operation_journal.dart';
import '../../state/profile_theme_sync.dart';
import '../../state/profile_workspace_sync.dart';
import '../../state/profiles.dart';
import '../../state/repo_watcher.dart';
import '../../state/settings_controller.dart';
import '../../state/update_controller.dart';
import '../../state/workspace.dart';
import '../terminal/terminal_panel.dart';
import '../common/progress_top_bar.dart';
import '../common/toast_overlay.dart';
import '../profiles/first_profile_screen.dart';
import '../welcome/welcome_screen.dart';
import '../workspace/workspace_view.dart';
import 'app_bottom_bar.dart';
import 'app_status_bar.dart';
import 'app_tab_bar.dart';
import 'app_toolbar.dart';
import 'keyboard_shortcuts.dart';
import 'quit_guard.dart';
import 'update_banner.dart';
import '../../l10n/gen/app_localizations.dart';

/// Root application scaffold: chrome bars framing either the workspace (a repo
/// is open) or the Welcome screen, with global overlays on top.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the auto-fetch scheduler, per-profile theme + workspace sync and the
    // disk watcher alive for the app's lifetime.
    ref.watch(autoFetchProvider);
    ref.watch(profileThemeSyncProvider);
    ref.watch(profileWorkspaceSyncProvider);
    ref.watch(repoWatcherProvider);
    ref.watch(openFilesSyncProvider);

    // No profile yet → block on the mandatory first-profile screen. Everything
    // (groups, repos) belongs to a profile, so one must exist first.
    if (ref.watch(profilesProvider.select((s) => s.active == null))) {
      return const FirstProfileScreen();
    }

    final hasRepo = ref.watch(workspaceProvider.select((w) => w.hasRepo));

    return Scaffold(
      body: QuitGuard(
        child: KeyboardShortcuts(
          child: Stack(
            children: [
              Column(
                children: [
                  const AppToolbar(),
                  const AppTabBar(),
                  Expanded(
                    child: hasRepo
                        ? Row(
                            children: [
                              // 'rail' group-switcher style docks a vertical
                              // group rail at the far left of the workspace.
                              if (ref.watch(
                                    settingsProvider.select(
                                      (s) => s.groupStyle,
                                    ),
                                  ) ==
                                  'rail')
                                const GroupRail(),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Expanded(child: WorkspaceView()),
                                    if (ref.watch(
                                      settingsProvider.select(
                                        (st) => st.terminalOpen,
                                      ),
                                    ))
                                      const TerminalPanel(),
                                    const AppBottomBar(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const WelcomeScreen(),
                  ),
                  const UpdateBanner(),
                  const AppStatusBar(),
                ],
              ),
              const ProgressTopBar(),
              const ToastOverlay(),
              const _StartupNotices(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Emits a one-time warning toast for each operation the journal found still
/// pending at launch (i.e. interrupted by a crash last session).
class _StartupNotices extends ConsumerStatefulWidget {
  const _StartupNotices();

  @override
  ConsumerState<_StartupNotices> createState() => _StartupNoticesState();
}

class _StartupNoticesState extends ConsumerState<_StartupNotices> {
  @override
  void initState() {
    final l = AppLocalizations.of(context);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notices = ref.read(interruptedOpsProvider);
      if (notices.isNotEmpty) {
        ref
            .read(toastProvider.notifier)
            .show(
              l.shellPrevOpUnfinished,
              description: notices.join('\n'),
              kind: ToastKind.error,
            );
      }

      if (!mounted) return;
      final consent = ref.read(settingsProvider).updateConsent;
      if (consent.isEmpty) {
        // First launch: put the question once and record the answer. Until it
        // is answered nothing reaches the network.
        showUpdateConsentDialog(context, ref);
      } else if (consent == 'on') {
        ref.read(updateStatusProvider.notifier).check();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
