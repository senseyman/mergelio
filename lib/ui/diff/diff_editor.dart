import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/diff_document.dart';
import '../../state/diff_target.dart';
import '../../state/file_editor.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';
import '../common/file_text_editor.dart';
import '../../l10n/gen/app_localizations.dart';

/// Full-text editor for an uncommitted file, shown in place of the diff body.
/// Saving writes the working tree and returns to the diff; the result is left
/// unstaged, and undo restores the previous bytes.
class DiffEditor extends ConsumerWidget {
  final DiffTarget target;
  const DiffEditor({super.key, required this.target});

  void _exit(WidgetRef ref) {
    ref.read(diffEditorDirtyProvider.notifier).state = false;
    ref.read(diffEditingProvider.notifier).state = null;
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    if (ref.read(diffEditorDirtyProvider)) {
      final ok = await confirmDestructive(
        ref,
        context,
        title: l.diffDiscardEditsTitle,
        body: l.diffDiscardEditsBody(target.path),
        confirmLabel: l.discard,
      );
      if (!ok) return;
    }
    _exit(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return FileTextEditor(
      repoPath: target.repoPath,
      relPath: target.path,
      onDirtyChanged: (dirty) =>
          ref.read(diffEditorDirtyProvider.notifier).state = dirty,
      onSave: (path, text) => ref
          .read(repoActionsProvider(target.repoPath))
          .saveFileText(path, text),
      onSaved: () {
        ref.invalidate(diffDocumentProvider(target));
        ref.invalidate(editableFileProvider(target));
        _exit(ref);
      },
      onCancel: () => _cancel(context, ref),
      footerBuilder: (context, controls) => _bar(t, context, ref, controls),
    );
  }

  Widget _bar(
    AppTokens t,
    BuildContext context,
    WidgetRef ref,
    FileEditorControls controls,
  ) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: t.border)),
    ),
    child: Row(
      children: [
        Flexible(
          child: Text(
            'Editing the working tree — saved changes stay unstaged',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.textFaint, fontSize: 11),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: controls.saving ? null : () => _cancel(context, ref),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: controls.saving ? null : controls.save,
          child: Text(AppLocalizations.of(context).save),
        ),
      ],
    ),
  );
}
