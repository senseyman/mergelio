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
                  // Wrap, not Row: a dialog offering three choices runs out of
                  // width at large text scales, and a second line beats a
                  // clipped button.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: actions,
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
}) => showAppModal<String>(
  context: context,
  title: title,
  icon: Icons.edit_outlined,
  width: 420,
  // The field + its buttons live in a stateful widget so the controller is
  // disposed with the route (after the exit animation), never while the
  // dialog is still transitioning out.
  body: _InputDialogBody(
    label: label,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class _InputDialogBody extends StatefulWidget {
  final String label;
  final String initial;
  final String confirmLabel;
  const _InputDialogBody({
    required this.label,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_InputDialogBody> createState() => _InputDialogBodyState();
}

class _InputDialogBodyState extends State<_InputDialogBody> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          style: TextStyle(color: t.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            labelText: widget.label.isEmpty ? null : widget.label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
          ],
        ),
      ],
    );
  }
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
