import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/feedback.dart';

/// Bottom-right stack of toasts. Mount once above the app shell.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider);
    final t = context.tokens;
    if (toasts.isEmpty) return const SizedBox.shrink();

    Color edge(ToastKind k) => switch (k) {
      ToastKind.success => t.success,
      ToastKind.warning => t.warning,
      ToastKind.error => t.danger,
      ToastKind.info => t.accent,
    };

    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final toast in toasts)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(minWidth: 260, maxWidth: 380),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: t.bgElevated,
                borderRadius: BorderRadius.circular(t.rCard),
                border: Border.all(color: t.border),
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: edge(toast.kind), width: 3),
                ),
                borderRadius: BorderRadius.circular(t.rCard),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          toast.title,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (toast.description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              toast.description!,
                              style: TextStyle(
                                color: t.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (toast.action != null) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () {
                        toast.action!.onPressed();
                        ref.read(toastProvider.notifier).dismiss(toast.id);
                      },
                      child: Text(toast.action!.label),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
