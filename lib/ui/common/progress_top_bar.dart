import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/feedback.dart';

/// Thin progress strip pinned to the very top while an operation runs.
class ProgressTopBar extends ConsumerWidget {
  const ProgressTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyProvider);
    if (busy == null) return const SizedBox.shrink();
    final t = context.tokens;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: busy.progress,
          minHeight: 3,
          backgroundColor: Colors.transparent,
          color: t.accent,
        ),
      ),
    );
  }
}
