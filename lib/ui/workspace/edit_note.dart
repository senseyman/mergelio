import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/git_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../common/dialogs.dart';

/// Reads the note on [sha], lets the user edit it and writes it back. Shared
/// by the graph's context menu and the commit details panel. The note is read
/// here rather than trusted from the panel, so the dialog always starts from
/// what git has now.
Future<void> editCommitNote(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  required String sha,
}) async {
  // Read before the dialog: `ref` belongs to a widget the modal outlives.
  final actions = ref.read(repoActionsProvider(repoPath));
  final toasts = ref.read(toastProvider.notifier);
  final l = AppLocalizations.of(context);
  final String? current;
  try {
    current = await actions.note(sha);
  } on GitException catch (e) {
    // An empty editor over a note that is there would overwrite it on Save.
    toasts.show(
      l.cdNoteUnreadable,
      description: e.result?.err ?? e.message,
      kind: ToastKind.error,
    );
    return;
  }
  if (!context.mounted) return;
  final edited = await showNoteDialog(context, initial: current ?? '');
  if (edited == null) return;
  await actions.setNote(sha, edited);
}

/// Multi-line note editor, titled "Add" or "Edit" by whether [initial] holds
/// a note. Returns the trimmed text — empty when the user cleared it, which
/// removes the note — or null on cancel.
Future<String?> showNoteDialog(
  BuildContext context, {
  required String initial,
}) {
  final l = AppLocalizations.of(context);
  return showAppModal<String>(
    context: context,
    title: initial.isEmpty ? l.noteAddTitle : l.noteEditTitle,
    icon: Icons.sticky_note_2_outlined,
    width: 520,
    body: _NoteBody(initial: initial),
  );
}

class _NoteBody extends StatefulWidget {
  final String initial;
  const _NoteBody({required this.initial});

  @override
  State<_NoteBody> createState() => _NoteBodyState();
}

class _NoteBodyState extends State<_NoteBody> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          minLines: 5,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          style: TextStyle(color: t.textPrimary, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.noteHint,
          style: TextStyle(color: t.textFaint, fontSize: 11.5, height: 1.4),
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
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
              child: Text(l.save),
            ),
          ],
        ),
      ],
    );
  }
}
