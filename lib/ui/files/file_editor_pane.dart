import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/open_files.dart';
import '../../state/unsaved_guard.dart';
import '../common/dialogs.dart';
import '../common/file_text_editor.dart';
import '../workspace/panel_placeholder.dart';
import '../../l10n/gen/app_localizations.dart';

/// Right side of Files mode: a strip of open files over the editor for
/// whichever one is on top. Every open file stays mounted, so switching tabs
/// keeps unsaved text and the caret where they were.
class FileEditorPane extends ConsumerStatefulWidget {
  final String repoPath;
  const FileEditorPane({super.key, required this.repoPath});

  @override
  ConsumerState<FileEditorPane> createState() => FileEditorPaneState();
}

class FileEditorPaneState extends ConsumerState<FileEditorPane> {
  /// One handle per open file, so a tab can be saved from its close button.
  final _handles = <String, FileEditorHandle>{};

  String get repoPath => widget.repoPath;

  /// Held rather than read through `ref`, which is off limits by the time
  /// this pane is being torn down.
  late final UnsavedGuards _guards;
  late final OpenFilesNotifier _files;

  @override
  void initState() {
    super.initState();
    _guards = ref.read(unsavedGuardsProvider)
      ..register(repoPath, confirmClosingAll);
    _files = ref.read(openFilesProvider(repoPath).notifier);
  }

  @override
  void dispose() {
    _guards.unregister(repoPath);
    // The editors are going with this pane, and their unsaved text with them,
    // so nothing may still claim to be unsaved once they are gone. Left until
    // the teardown is over: notifying while this element is being unmounted
    // would rebuild a widget that no longer exists.
    final files = _files;
    Future.microtask(() {
      // The whole repository may have gone away in the meantime.
      if (files.mounted) files.clearDirty();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final open = ref.watch(openFilesProvider(repoPath));
    _handles.removeWhere((path, _) => !open.paths.contains(path));

    if (open.paths.isEmpty) {
      return PanelPlaceholder(
        title: l.filesEditor,
        hint: l.fepOpenAFile,
        background: t.bgApp,
      );
    }

    return Container(
      color: t.bgApp,
      child: Column(
        children: [
          _TabStrip(
            open: open,
            onSelect: _files.activate,
            onClose: (path) => closeTab(path),
          ),
          Expanded(
            child: Stack(
              children: [
                for (final path in open.paths)
                  Offstage(
                    offstage: path != open.active,
                    child: _editor(t, path, gone: open.isGone(path)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(AppTokens t, String path, {required bool gone}) => Column(
    children: [
      if (gone) _GoneBanner(t: t),
      Expanded(
        child: FileTextEditor(
          key: ValueKey(path),
          repoPath: repoPath,
          relPath: path,
          handle: _handles.putIfAbsent(path, FileEditorHandle.new),
          // A file the user deleted must not come back because an editor was
          // left open on it.
          onSave: gone ? (_, _) async => false : null,
          onDirtyChanged: (dirty) => _files.setDirty(path, dirty),
        ),
      ),
    ],
  );

  /// Closes one tab, asking about unsaved text first. Returns false when the
  /// user backed out, so a caller closing several can stop.
  Future<bool> closeTab(String path) async {
    if (ref.read(openFilesProvider(repoPath)).isDirty(path)) {
      final choice = await showUnsavedDialog(context, paths: [path]);
      switch (choice) {
        case UnsavedChoice.cancel:
          return false;
        case UnsavedChoice.save:
          await _handles[path]?.save();
          // A save that failed leaves the text where it is rather than
          // closing over it.
          if (!mounted || ref.read(openFilesProvider(repoPath)).isDirty(path)) {
            return false;
          }
        case UnsavedChoice.discard:
          break;
      }
    }
    _files.close(path);
    return true;
  }

  /// Asks once about every unsaved editor, for a caller about to take the
  /// whole pane away — leaving Files mode, closing the repository, quitting.
  Future<bool> confirmClosingAll() async {
    final dirty = ref.read(openFilesProvider(repoPath)).dirty.toList()..sort();
    if (dirty.isEmpty) return true;
    final choice = await showUnsavedDialog(context, paths: dirty);
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        return true;
      case UnsavedChoice.save:
        for (final path in dirty) {
          await _handles[path]?.save();
        }
        if (!mounted) return true;
        return ref.read(openFilesProvider(repoPath)).dirty.isEmpty;
    }
  }
}

/// The file is no longer where the editor found it.
class _GoneBanner extends StatelessWidget {
  final AppTokens t;
  const _GoneBanner({required this.t});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    color: t.danger.withValues(alpha: 0.14),
    child: Text(
      AppLocalizations.of(context).fepDeletedOnDisk,
      style: TextStyle(color: t.danger, fontSize: 11),
    ),
  );
}

class _TabStrip extends StatelessWidget {
  final OpenFiles open;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  const _TabStrip({
    required this.open,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      // Many open files scroll sideways rather than shrinking to unreadable
      // slivers, matching the repo tab bar above it.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final path in open.paths)
              _Tab(
                path: path,
                active: path == open.active,
                dirty: open.isDirty(path),
                gone: open.isGone(path),
                onSelect: () => onSelect(path),
                onClose: () => onClose(path),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String path;
  final bool active;
  final bool dirty;
  final bool gone;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  const _Tab({
    required this.path,
    required this.active,
    required this.dirty,
    required this.gone,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final name = path.split('/').last;
    return Tooltip(
      message: path,
      child: Listener(
        // Middle-click closes, the way it does everywhere else tabs exist.
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) onClose();
        },
        child: InkWell(
          onTap: onSelect,
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: active ? t.bgPanel : Colors.transparent,
              border: Border(
                right: BorderSide(color: t.border),
                bottom: BorderSide(
                  color: active ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: active ? t.textPrimary : t.textMuted,
                    fontSize: 12,
                    decoration: gone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (dirty) ...[
                  const SizedBox(width: 6),
                  Container(
                    key: ValueKey('unsaved:$path'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Tooltip(
                  message: l.filesClosePath(path),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 12, color: t.textFaint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
