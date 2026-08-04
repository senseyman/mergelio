import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/file_edit.dart';
import '../../domain/text_find.dart';
import '../../state/file_editor.dart';
import '../../state/repo_actions.dart';
import '../common/confirm.dart';
import '../diff/linked_scroll.dart';
import '../diff/syntax_style.dart';

/// What a host's footer may do with the editor above it.
class FileEditorControls {
  /// True while a save is in flight, so buttons can be disabled.
  final bool saving;
  final Future<void> Function() save;
  const FileEditorControls({required this.saving, required this.save});
}

/// A handle a host keeps so it can save an editor it does not otherwise talk
/// to — closing an unsaved tab, for one, has to offer Save from outside the
/// editor. Null while the editor is not mounted or is showing a blocker.
class FileEditorHandle {
  Future<void> Function()? _save;

  bool get canSave => _save != null;

  Future<void> save() async => _save?.call();
}

/// Editing surface for one working-tree file: loads it, refuses what cannot be
/// edited, tracks unsaved text and writes it back. Both the diff sheet and
/// Files mode host this widget, so the guards and the save path cannot drift
/// apart between them.
class FileTextEditor extends ConsumerStatefulWidget {
  final String repoPath;

  /// Repo-relative, `/`-separated.
  final String relPath;

  /// Reports whether the field holds text that is not on disk. Fires only when
  /// the answer changes.
  final ValueChanged<bool>? onDirtyChanged;

  /// Writes [text] to the repo-relative [path] and reports whether it landed.
  /// Defaults to the repository's own save, which leaves the result unstaged.
  final Future<bool> Function(String path, String text)? onSave;

  /// Called after text has been written, for a host that closes on save.
  final VoidCallback? onSaved;

  /// Bound to Escape. Null leaves the key to the surrounding widgets.
  final VoidCallback? onCancel;

  /// Row shown under the field, given what it can drive.
  final Widget Function(BuildContext, FileEditorControls)? footerBuilder;

  /// Filled in with this editor's save while it is mounted and editable.
  final FileEditorHandle? handle;

  const FileTextEditor({
    super.key,
    required this.repoPath,
    required this.relPath,
    this.onDirtyChanged,
    this.onSave,
    this.onSaved,
    this.onCancel,
    this.footerBuilder,
    this.handle,
  });

  @override
  ConsumerState<FileTextEditor> createState() => _FileTextEditorState();
}

class _FileTextEditorState extends ConsumerState<FileTextEditor> {
  /// The bytes as they stand on disk — what dirtiness is measured against.
  EditableFile? _file;
  SyntaxHighlightingController? _controller;
  bool _saving = false;
  bool _dirty = false;

  /// Holds the text and its line numbers at the same offset.
  final _scroll = LinkedScrollController();

  /// How many lines the gutter is showing, so typing only rebuilds it when
  /// the answer changes rather than on every keystroke.
  int _lines = 1;

  bool _finding = false;
  final _query = TextEditingController();
  final _replacement = TextEditingController();
  bool _caseSensitive = false;

  /// Which match Next / Previous is standing on.
  int _current = 0;

  /// The editor's own edit history. Without it ⌘Z inside an open file would
  /// reach the app-level binding and undo the last git operation instead.
  final _undo = UndoHistoryController();

  @override
  void dispose() {
    if (widget.handle?._save == _save) widget.handle?._save = null;
    _controller?.dispose();
    _query.dispose();
    _replacement.dispose();
    _scroll.dispose();
    _undo.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller?.text ?? '';
    final lines = _lineCount(text);
    if (lines != _lines) setState(() => _lines = lines);
    final dirty = text != (_file?.text ?? '');
    if (dirty == _dirty) return;
    _dirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  static int _lineCount(String text) => '\n'.allMatches(text).length + 1;

  List<TextMatch> get _matches => findMatches(
    _controller?.text ?? '',
    _query.text,
    caseSensitive: _caseSensitive,
  );

  void _openFind() {
    setState(() => _finding = true);
    _goToMatch(0);
  }

  void _closeFind() => setState(() {
    _finding = false;
    _query.clear();
  });

  /// Shows match [at] by selecting it, so Next reads as movement through the
  /// file rather than only as a changing count.
  void _goToMatch(int at) {
    final matches = _matches;
    if (matches.isEmpty || _controller == null) return;
    final match = matches[at.clamp(0, matches.length - 1)];
    _controller!.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  void _onQueryChanged() => setState(() {
    _current = 0;
    _goToMatch(0);
  });

  void _step({required bool forward}) {
    final matches = _matches;
    if (matches.isEmpty) return;
    final from = forward ? matches[_current].end : matches[_current].start;
    final at = nextMatch(matches, from, forward: forward) ?? 0;
    setState(() => _current = at);
    _goToMatch(at);
  }

  void _replaceCurrent() {
    final matches = _matches;
    final ctl = _controller;
    if (matches.isEmpty || ctl == null) return;
    final at = _current.clamp(0, matches.length - 1);
    ctl.text = replaceMatch(ctl.text, matches[at], _replacement.text);
    setState(() => _current = 0);
    _goToMatch(0);
  }

  void _replaceAll() {
    final ctl = _controller;
    if (ctl == null) return;
    ctl.text = replaceAllMatches(
      ctl.text,
      _query.text,
      _replacement.text,
      caseSensitive: _caseSensitive,
    );
    setState(() => _current = 0);
  }

  Future<void> _save() async {
    final ctl = _controller;
    if (ctl == null || _saving) return;
    final onDisk = File('${widget.repoPath}/${widget.relPath}');
    if (await fileChangedSince(onDisk, _file?.loadedAt)) {
      if (!mounted) return;
      final ok = await confirmDestructive(
        ref,
        context,
        title: 'File changed on disk',
        body:
            'Something else wrote ${widget.relPath} while it was open here. '
            'Saving replaces those changes with this text.',
        confirmLabel: 'Overwrite',
      );
      if (!ok) return;
    }
    final text = ctl.text;
    setState(() => _saving = true);
    bool saved;
    try {
      final save =
          widget.onSave ??
          (String path, String text) => ref
              .read(repoActionsProvider(widget.repoPath))
              .saveFileText(path, text);
      saved = await save(widget.relPath, text);
    } finally {
      // Whatever happens, the buttons must come back — a stuck _saving would
      // leave the text trapped in a dead editor.
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    // A refused or failed save leaves the editor open holding the text; the
    // reason has already been reported as a toast.
    if (!saved) return;
    // What was written is now the baseline, so the field reads clean even
    // though the editor stays open on it.
    _file = EditableFile(text: text);
    _onTextChanged();
    ref.invalidate(
      editableFileForPathProvider(FileRef(widget.repoPath, widget.relPath)),
    );
    widget.onSaved?.call();
    // Picking the mtime back up keeps the external-change check alive for the
    // next save; until it lands, the check simply passes.
    unawaited(_restampBaseline(onDisk, text));
  }

  /// Re-reads the mtime of what was just written. Left off the save path so a
  /// slow stat cannot hold up an editor that is already clean.
  Future<void> _restampBaseline(File file, String text) async {
    DateTime stamp;
    try {
      stamp = await file.lastModified();
    } on FileSystemException {
      return;
    }
    // Another save may have landed in the meantime; that one owns the baseline.
    if (!mounted || _file?.text != text || _file?.loadedAt != null) return;
    _file = EditableFile(text: text, loadedAt: stamp);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ref
        .watch(
          editableFileForPathProvider(FileRef(widget.repoPath, widget.relPath)),
        )
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
            if (_controller == null) {
              _controller = SyntaxHighlightingController(
                tokens: t,
                text: file.text,
              )..addListener(_onTextChanged);
              _lines = _lineCount(file.text);
            }
            // The theme can be switched while the editor is open.
            _controller!.tokens = t;
            return _editor(t);
          },
        );
  }

  Widget _editor(AppTokens t) {
    widget.handle?._save = _save;
    final footer = widget.footerBuilder?.call(
      context,
      FileEditorControls(saving: _saving, save: _save),
    );
    final escape = _finding ? _closeFind : widget.onCancel;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.escape): ?escape,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undo.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _undo.redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _undo.redo,
      },
      child: Column(
        children: [
          if (_finding) _findBar(t),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _gutter(t),
                Expanded(
                  child: TextField(
                    key: const ValueKey('editor:body'),
                    controller: _controller,
                    scrollController: _scroll,
                    undoController: _undo,
                    maxLines: null,
                    expands: true,
                    autofocus: true,
                    textAlignVertical: TextAlignVertical.top,
                    cursorColor: t.accent,
                    style: _codeStyle(t.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    );
  }

  static TextStyle _codeStyle(Color color) => TextStyle(
    color: color,
    fontSize: 12.5,
    fontFamily: 'monospace',
    height: 1.35,
  );

  /// Line numbers beside the text, held at the same offset by the shared
  /// controller. Numbers count lines as the file stores them, so a line long
  /// enough to wrap takes more rows than its number suggests.
  Widget _gutter(AppTokens t) => Container(
    key: const ValueKey('editor:gutter'),
    decoration: BoxDecoration(
      color: t.bgPanel,
      border: Border(right: BorderSide(color: t.border)),
    ),
    child: SingleChildScrollView(
      controller: _scroll,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= _lines; i++)
            Text('$i', style: _codeStyle(t.textFaint)),
        ],
      ),
    ),
  );

  Widget _findBar(AppTokens t) {
    final matches = _matches;
    final count = _query.text.isEmpty
        ? ''
        : (matches.isEmpty
              ? 'No results'
              : '${_current.clamp(0, matches.length - 1) + 1} of '
                    '${matches.length}');
    return Container(
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(child: _findField(t, 'find:query', _query, 'Find')),
          const SizedBox(width: 8),
          Expanded(
            child: _findField(t, 'find:replace', _replacement, 'Replace with'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              count,
              style: TextStyle(color: t.textFaint, fontSize: 11),
            ),
          ),
          _findButton(
            t,
            'find:case',
            Icons.text_fields,
            'Match case',
            () => setState(() {
              _caseSensitive = !_caseSensitive;
              _current = 0;
            }),
            on: _caseSensitive,
          ),
          _findButton(
            t,
            'find:prev',
            Icons.keyboard_arrow_up,
            'Previous match',
            () => _step(forward: false),
          ),
          _findButton(
            t,
            'find:next',
            Icons.keyboard_arrow_down,
            'Next match',
            () => _step(forward: true),
          ),
          _findButton(
            t,
            'find:replaceOne',
            Icons.find_replace,
            'Replace this match',
            _replaceCurrent,
          ),
          _findButton(
            t,
            'find:replaceAll',
            Icons.all_inclusive,
            'Replace all',
            _replaceAll,
          ),
          _findButton(t, 'find:close', Icons.close, 'Close', _closeFind),
        ],
      ),
    );
  }

  Widget _findField(
    AppTokens t,
    String key,
    TextEditingController controller,
    String hint,
  ) => TextField(
    key: ValueKey(key),
    controller: controller,
    autofocus: key == 'find:query',
    onChanged: (_) => _onQueryChanged(),
    style: TextStyle(color: t.textPrimary, fontSize: 12),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: const OutlineInputBorder(),
    ),
  );

  Widget _findButton(
    AppTokens t,
    String key,
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool on = false,
  }) => Tooltip(
    message: tooltip,
    child: InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 15, color: on ? t.accent : t.textMuted),
      ),
    ),
  );

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
}
