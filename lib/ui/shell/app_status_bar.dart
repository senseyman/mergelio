import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/workspace.dart';

/// Bottom status strip: active repo, current branch, ahead/behind, identity.
/// Values are placeholders until repo status reads land in a later stage.
class AppStatusBar extends ConsumerWidget {
  const AppStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final tab = ref.watch(workspaceProvider).activeTab;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: t.textMuted, fontSize: 11),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: t.success),
            const SizedBox(width: 6),
            Text(tab?.name ?? 'No repository'),
            if (tab != null) ...[
              _dot(t),
              Icon(Icons.call_split, size: 12, color: t.textMuted),
              const SizedBox(width: 4),
              const Text('main'),
              _dot(t),
              const Text('↑0 ↓0'),
            ],
            const Spacer(),
            const Text('Maria (work)'),
          ],
        ),
      ),
    );
  }

  Widget _dot(AppTokens t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text('·', style: TextStyle(color: t.textFaint)),
  );
}
