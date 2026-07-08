import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auto_fetch.dart';
import '../../state/feedback.dart';
import '../../state/operation_journal.dart';
import '../../state/terminal.dart';
import '../../state/workspace.dart';
import '../terminal/terminal_panel.dart';
import '../common/progress_top_bar.dart';
import '../common/toast_overlay.dart';
import '../welcome/welcome_screen.dart';
import '../workspace/workspace_view.dart';
import 'app_bottom_bar.dart';
import 'app_status_bar.dart';
import 'app_tab_bar.dart';
import 'app_toolbar.dart';
import 'keyboard_shortcuts.dart';

/// Root application scaffold: chrome bars framing either the workspace (a repo
/// is open) or the Welcome screen, with global overlays on top.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRepo = ref.watch(workspaceProvider.select((w) => w.hasRepo));
    // Keep the auto-fetch scheduler alive for the app's lifetime.
    ref.watch(autoFetchProvider);

    return Scaffold(
      body: KeyboardShortcuts(
        child: Stack(
          children: [
            Column(
              children: [
                const AppToolbar(),
                const AppTabBar(),
                Expanded(
                  child: hasRepo
                      ? Column(
                          children: [
                            const Expanded(child: WorkspaceView()),
                            if (ref.watch(terminalVisibleProvider))
                              const TerminalPanel(),
                            const AppBottomBar(),
                          ],
                        )
                      : const WelcomeScreen(),
                ),
                const AppStatusBar(),
              ],
            ),
            const ProgressTopBar(),
            const ToastOverlay(),
            const _StartupNotices(),
          ],
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
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notices = ref.read(interruptedOpsProvider);
      if (notices.isEmpty) return;
      ref
          .read(toastProvider.notifier)
          .show(
            'A previous operation may not have finished',
            description: notices.join('\n'),
            kind: ToastKind.error,
          );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
