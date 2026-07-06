import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/feedback.dart';
import 'shell_widgets.dart';

/// Bottom action bar: undo/redo pinned left, git operations centred with a
/// single divider between the network and branch-ops groups.
class AppBottomBar extends ConsumerWidget {
  const AppBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    void soon(String what) => ref
        .read(toastProvider.notifier)
        .show(what, description: 'Coming in a later stage');

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Row(
              children: const [
                // Wired to real history once undoable git ops land.
                BarIconButton(
                  icon: Icons.undo,
                  tooltip: 'Undo (⌘Z)',
                  onPressed: null,
                ),
                BarIconButton(
                  icon: Icons.redo,
                  tooltip: 'Redo (⌘⇧Z)',
                  onPressed: null,
                ),
              ],
            ),
          ),
          // Network and branch-ops groups split by a divider pinned to the
          // exact horizontal centre: each group hugs its side of the divider.
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BarTextButton(
                          icon: Icons.download_outlined,
                          label: 'Fetch',
                          onPressed: () => soon('Fetch'),
                        ),
                        BarTextButton(
                          icon: Icons.south_west,
                          label: 'Pull',
                          onPressed: () => soon('Pull'),
                        ),
                        BarTextButton(
                          icon: Icons.north_east,
                          label: 'Push',
                          onPressed: () => soon('Push'),
                        ),
                      ],
                    ),
                  ),
                ),
                const BarSeparator(),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BarTextButton(
                          icon: Icons.call_split,
                          label: 'Branch',
                          onPressed: () => soon('Branch'),
                        ),
                        BarTextButton(
                          icon: Icons.merge,
                          label: 'Merge',
                          onPressed: () => soon('Merge'),
                        ),
                        BarTextButton(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stash',
                          onPressed: () => soon('Stash'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
