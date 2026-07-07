import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';

/// Standard modal card: header (icon · title · ✕) / body / footer actions.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required String title,
  IconData? icon,
  required Widget body,
  List<Widget> actions = const [],
  double width = 540,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final t = ctx.tokens;
      return Dialog(
        backgroundColor: t.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.rCard),
          side: BorderSide(color: t.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: t.textPrimary),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: AppFonts.disp(size: 18, color: t.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: t.textMuted,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: body,
                ),
              ),
              if (actions.isNotEmpty) ...[
                Divider(height: 1, color: t.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final a in actions)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: a,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Single-line text prompt. Returns the entered value (trimmed, non-empty) or
/// null on cancel. [initial] pre-fills and selects the field.
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String confirmLabel = 'OK',
}) {
  final controller = TextEditingController(text: initial);
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: initial.length,
  );
  final result = showAppModal<String>(
    context: context,
    title: title,
    icon: Icons.edit_outlined,
    width: 420,
    body: Builder(
      builder: (ctx) {
        final t = ctx.tokens;
        void submit() {
          final v = controller.text.trim();
          if (v.isNotEmpty) Navigator.of(ctx).pop(v);
        }

        return TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) => submit(),
          style: TextStyle(color: t.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: label.isEmpty ? null : label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        );
      },
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.of(ctx).pop(v);
          },
          child: Text(confirmLabel),
        ),
      ),
    ],
  );
  return result.whenComplete(controller.dispose);
}

/// Confirmation gate for destructive actions. Returns true when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
}) async {
  final t = context.tokens;
  final result = await showAppModal<bool>(
    context: context,
    title: title,
    icon: Icons.warning_amber_rounded,
    width: 440,
    body: Text(
      body,
      style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.tokens.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ),
    ],
  );
  return result ?? false;
}

/// Cursor-anchored flat context menu.
Future<T?> showContextMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<PopupMenuEntry<T>> items,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
    color: context.tokens.bgElevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(context.tokens.rCard),
      side: BorderSide(color: context.tokens.border),
    ),
  );
}
