import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/file_edit.dart';
import '../../state/diff_document.dart';
import '../../state/diff_target.dart';
import '../../state/file_editor.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';
import 'syntax_style.dart';

/// Full-text editor for an uncommitted file, shown in place of the diff body.
/// Saving writes the working tree and returns to the diff; the result is left
/// unstaged, and undo restores the previous bytes.
class DiffEditor extends ConsumerStatefulWidget {
  final DiffTarget target;
  const DiffEditor({super.key, required this.target});

  @override
  ConsumerState<DiffEditor> createState() => _DiffEditorState();
}

class _DiffEditorState extends ConsumerState<DiffEditor> {
  EditableFile? _file;
  SyntaxHighlightingController? _controller;
  bool _saving = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _exit() {
    ref.read(diffEditorDirtyProvider.notifier).state = false;
    ref.read(diffEditingProvider.notifier).state = null;
  }

  /// Keeps [diffEditorDirtyProvider] in step with the field, so closing the
  /// sheet can tell whether there is unsaved text to lose.
  void _onTextChanged() {
    final dirty = _controller?.text != (_file?.text ?? '');
    if (ref.read(diffEditorDirtyProvider) != dirty) {
      ref.read(diffEditorDirtyProvider.notifier).state = dirty;
    }
  }

  Future<void> _cancel() async {
    final ctl = _controller;
    if (ctl != null && ctl.text != (_file?.text ?? '')) {
      final ok = await confirmDestructive(
        ref,
        context,
        title: 'Discard edits?',
        body:
            'What you typed here has not been written to '
            '${widget.target.path}.',
        confirmLabel: 'Discard',
      );
      if (!ok) return;
    }
    _exit();
  }

  Future<void> _save() async {
    final ctl = _controller;
    if (ctl == null || _saving) return;
    final onDisk = File('${widget.target.repoPath}/${widget.target.path}');
    if (await fileChangedSince(onDisk, _file?.loadedAt)) {
      if (!mounted) return;
      final ok = await confirmDestructive(
        ref,
        context,
        title: 'File changed on disk',
        body:
            'Something else wrote ${widget.target.path} while it was open '
            'here. Saving replaces those changes with this text.',
        confirmLabel: 'Overwrite',
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    bool saved;
    try {
      saved = await ref
          .read(repoActionsProvider(widget.target.repoPath))
          .saveFileText(widget.target.path, ctl.text);
    } finally {
      // Whatever happens, the buttons must come back — a stuck _saving would
      // leave the text trapped in a dead editor.
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    // A refused or failed save leaves the editor open holding the text; the
    // reason has already been reported as a toast.
    if (!saved) return;
    ref.invalidate(diffDocumentProvider(widget.target));
    ref.invalidate(editableFileProvider(widget.target));
    _exit();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ref
        .watch(editableFileProvider(widget.target))
        .when(
          loading: () => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (e, _) => _message(t, 'Could not open this file'),
          data: (file) {
            if (!file.canEdit) return _message(t, file.blocker!);
            // The first delivery seeds the field; later rebuilds must not
            // clobber what has been typed since.
            _file ??= file;
            _controller ??= SyntaxHighlightingController(
              tokens: t,
              text: file.text,
            )..addListener(_onTextChanged);
            // The theme can be switched while the editor is open.
            _controller!.tokens = t;
            return _editor(t);
          },
        );
  }

  Widget _editor(AppTokens t) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              autofocus: true,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: t.accent,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12.5,
                fontFamily: 'monospace',
                height: 1.35,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
          _bar(t),
        ],
      ),
    );
  }

  Widget _message(AppTokens t, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: t.textFaint, fontSize: 12),
      ),
    ),
  );

  Widget _bar(AppTokens t) => Container(
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
          onPressed: _saving ? null : _cancel,
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
