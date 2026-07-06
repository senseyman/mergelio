import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/workspace.dart';
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
                          children: const [
                            Expanded(child: WorkspaceView()),
                            AppBottomBar(),
                          ],
                        )
                      : const WelcomeScreen(),
                ),
                const AppStatusBar(),
              ],
            ),
            const ProgressTopBar(),
            const ToastOverlay(),
          ],
        ),
      ),
    );
  }
}
