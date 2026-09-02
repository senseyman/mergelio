import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/commit_message.dart';
import '../../l10n/gen/app_localizations.dart';

export '../../domain/git/commit_message.dart' show CommitMessageParts;

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

/// Single-line text prompt. Returns the entered value (trimmed) or null on
/// cancel. [initial] pre-fills and selects the field.
///
/// By default an empty field cannot be confirmed, so a null result always
/// means "cancelled". Set [allowEmpty] when the value really is optional —
/// then confirming an empty field returns `''`, which is still distinct from
/// the null a cancel returns. Callers must keep telling those two apart:
/// treating null as "no value given" is how a cancelled prompt turns into an
/// action the user declined.
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String confirmLabel = 'OK',
  bool allowEmpty = false,
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
    allowEmpty: allowEmpty,
  ),
);

class _InputDialogBody extends StatefulWidget {
  final String label;
  final String initial;
  final String confirmLabel;
  final bool allowEmpty;
  const _InputDialogBody({
    required this.label,
    required this.initial,
    required this.confirmLabel,
    required this.allowEmpty,
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
    if (v.isNotEmpty || widget.allowEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
          ],
        ),
      ],
    );
  }
}

/// Commit message editor: a one-line summary over a multi-line description,
/// mirroring how the commit composer splits them. Returns the edited parts, or
/// null on cancel. An empty summary cannot be saved — a commit needs a subject.
Future<CommitMessageParts?> showCommitMessageDialog(
  BuildContext context, {
  String? title,
  String initialSummary = '',
  String initialDescription = '',
  String? confirmLabel,
}) => showAppModal<CommitMessageParts>(
  context: context,
  title: title ?? AppLocalizations.of(context).dlgEditCommitMessage,
  icon: Icons.edit_note_outlined,
  width: 520,
  body: _CommitMessageBody(
    initialSummary: initialSummary,
    initialDescription: initialDescription,
    confirmLabel: confirmLabel ?? AppLocalizations.of(context).save,
  ),
);

class _CommitMessageBody extends StatefulWidget {
  final String initialSummary;
  final String initialDescription;
  final String confirmLabel;
  const _CommitMessageBody({
    required this.initialSummary,
    required this.initialDescription,
    required this.confirmLabel,
  });

  @override
  State<_CommitMessageBody> createState() => _CommitMessageBodyState();
}

class _CommitMessageBodyState extends State<_CommitMessageBody> {
  late final _summary = TextEditingController(text: widget.initialSummary)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialSummary.length,
    );
  late final _description = TextEditingController(
    text: widget.initialDescription,
  );

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final s = _summary.text.trim();
    if (s.isEmpty) return;
    Navigator.of(
      context,
    ).pop((summary: s, description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final style = TextStyle(color: t.textPrimary, fontSize: 13);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _summary,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          style: style,
          decoration: InputDecoration(
            labelText: l.wtpSummary,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          style: style,
          decoration: InputDecoration(
            labelText: l.wtpDescription,
            alignLabelWithHint: true,
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
              child: Text(l.cancel),
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
  String? confirmLabel,
}) async {
  final l = AppLocalizations.of(context);
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
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ctx.tokens.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? AppLocalizations.of(ctx).confirmAction),
        ),
      ),
    ],
  );
  return result ?? false;
}

/// What to do with editor text that has not been written yet.
enum UnsavedChoice { save, discard, cancel }

/// Asked before unsaved editors are thrown away — closing a tab, leaving Files
/// mode, closing a repository or quitting. [paths] names every file at risk, so
/// one prompt covers a whole batch.
Future<UnsavedChoice> showUnsavedDialog(
  BuildContext context, {
  required List<String> paths,
}) async {
  final l = AppLocalizations.of(context);
  final t = context.tokens;
  final result = await showAppModal<UnsavedChoice>(
    context: context,
    title: l.commonUnsavedChanges,
    icon: Icons.edit_note_outlined,
    width: 460,
    body: Text(
      paths.length == 1
          ? l.dlgUnsavedOne(paths.single)
          : '${l.dlgUnsavedMany}\n\n'
                '${paths.map((p) => '· $p').join('\n')}',
      style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(UnsavedChoice.cancel),
          child: Text(l.cancel),
        ),
      ),
      Builder(
        builder: (ctx) => TextButton(
          style: TextButton.styleFrom(foregroundColor: ctx.tokens.danger),
          onPressed: () => Navigator.of(ctx).pop(UnsavedChoice.discard),
          child: Text(l.discard),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(UnsavedChoice.save),
          child: Text(l.save),
        ),
      ),
    ],
  );
  // Dismissing the dialog is a decision not to lose anything.
  return result ?? UnsavedChoice.cancel;
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
