import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../domain/project_menu.dart';
import '../../domain/project_ops.dart';
import '../../domain/project_status.dart';
import '../../domain/project_tree.dart';
import '../../domain/search.dart';
import '../../domain/reveal.dart';
import '../../state/feedback.dart';
import '../../state/open_files.dart';
import '../../state/project_files.dart';
import '../../state/project_ops_provider.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/search.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../common/file_tree_view.dart';

/// Directories the user has opened in the navigator, per repository. Bounded
/// by what has actually been clicked, so it stays small even in a huge tree.
final expandedDirsProvider = StateProvider.family<Set<String>, String>(
  (ref, repoPath) => const {},
);

/// The row the keyboard is on, per repository. Distinct from the selection:
/// moving the cursor browses, Enter is what opens.
final navCursorProvider = StateProvider.family<String?, String>(
  (ref, repoPath) => null,
);

/// Left panel of Files mode: the repository's directory tree, read one folder
/// at a time as folders are opened.
class ProjectNavPanel extends ConsumerStatefulWidget {
  final String repoPath;
  final VoidCallback? onCollapse;
  const ProjectNavPanel({super.key, required this.repoPath, this.onCollapse});

  @override
  ConsumerState<ProjectNavPanel> createState() => _ProjectNavPanelState();
}

class _ProjectNavPanelState extends ConsumerState<ProjectNavPanel> {
  final _focus = FocusNode(debugLabel: 'project navigator');

  /// The rows as last built — what the arrow keys walk.
  List<ProjectRow> _rows = const [];

  String get repoPath => widget.repoPath;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final expanded = ref.watch(expandedDirsProvider(repoPath));
    // The file on top of the editor is what the tree marks as selected, so
    // switching tabs moves the highlight with it.
    final selected = ref.watch(
      openFilesProvider(repoPath).select((f) => f.active),
    );
    final hideIgnored = ref.watch(
      settingsProvider.select((s) => s.filesHideIgnored),
    );

    // Watch the root plus every opened directory. A directory that is not
    // open is never read, which is what keeps a large tree cheap.
    final loaded = <String, DirListing>{};
    final ignored = <String>{};
    for (final dir in <String>['', ...expanded]) {
      final key = DirKey(repoPath, dir);
      final listing = ref.watch(dirListingProvider(key)).valueOrNull;
      if (listing != null) loaded[dir] = listing;
      ignored.addAll(ref.watch(ignoredInDirProvider(key)).valueOrNull ?? {});
    }

    // Null while the read is in flight as well as when it failed: either way
    // nothing is known yet, and an unknown entry carries no badge.
    final tracked = ref.watch(trackedPathsProvider(repoPath)).valueOrNull;
    final working = indexWorking(
      ref.watch(repoDataProvider(repoPath)).valueOrNull?.working ?? const [],
    );

    final rows = flattenProject(
      loaded: loaded,
      expanded: expanded,
      hideIgnored: hideIgnored,
      ignored: ignored,
    );
    _rows = rows;
    final cursor = ref.watch(navCursorProvider(repoPath));

    EntryStatus statusOf(String path) => classifyEntry(
      relPath: path,
      tracked: tracked?.contains(path),
      ignored: ignored.contains(path),
      working: working,
    );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        decoration: BoxDecoration(
          color: t.bgPanel,
          border: Border(right: BorderSide(color: t.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              repoPath: repoPath,
              hideIgnored: hideIgnored,
              onToggleIgnored: () =>
                  ref.read(settingsProvider.notifier).toggleFilesHideIgnored(),
              onRefresh: () {
                for (final dir in <String>['', ...expanded]) {
                  ref.invalidate(dirListingProvider(DirKey(repoPath, dir)));
                }
              },
              onCollapse: widget.onCollapse,
            ),
            Expanded(
              // Right-clicking past the last row is how a project with no
              // folder to aim at gets its first file: the empty space stands
              // for the root. A row's own detector wins over this one.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (d) => _rootMenu(d.globalPosition),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: rows.length,
                  itemBuilder: (context, i) =>
                      _row(t, rows[i], selected, cursor, statusOf, working),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rows the cursor can land on. Loading, truncation and error rows are
  /// notices rather than destinations.
  List<ProjectRow> get _stops => [
    for (final r in _rows)
      if (r is ProjectDirRow || r is ProjectFileRow) r,
  ];

  void _moveCursor(int delta) {
    final stops = _stops;
    if (stops.isEmpty) return;
    final cursor = ref.read(navCursorProvider(repoPath));
    final at = stops.indexWhere((r) => r.path == cursor);
    // No cursor yet: the first press lands on the first row rather than
    // jumping into the middle of the tree.
    final next = at < 0 ? 0 : (at + delta).clamp(0, stops.length - 1);
    ref.read(navCursorProvider(repoPath).notifier).state = stops[next].path;
  }

  void _setExpanded(String path, bool open) {
    final set = {...ref.read(expandedDirsProvider(repoPath))};
    if (open ? !set.add(path) : !set.remove(path)) return;
    ref.read(expandedDirsProvider(repoPath).notifier).state = set;
  }

  ProjectRow? get _cursorRow {
    final cursor = ref.read(navCursorProvider(repoPath));
    for (final r in _stops) {
      if (r.path == cursor) return r;
    }
    return null;
  }

  /// Opens a file in the editor, or brings its tab forward when it is
  /// already open.
  void _open(String path) =>
      ref.read(openFilesProvider(repoPath).notifier).open(path);

  void _openCursor() {
    final row = _cursorRow;
    switch (row) {
      case ProjectFileRow():
        _open(row.path);
      case ProjectDirRow():
        _setExpanded(row.path, !row.open);
      case _:
        break;
    }
  }

  /// Right opens a folder; left closes it, or steps out to the folder holding
  /// the current row when there is nothing to close.
  void _horizontal(bool forward) {
    final row = _cursorRow;
    if (row == null) return;
    if (row is ProjectDirRow && row.open != forward) {
      _setExpanded(row.path, forward);
      return;
    }
    if (forward) return;
    final cut = row.path.lastIndexOf('/');
    if (cut < 0) return;
    ref.read(navCursorProvider(repoPath).notifier).state = row.path.substring(
      0,
      cut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveCursor(1);
      case LogicalKeyboardKey.arrowUp:
        _moveCursor(-1);
      case LogicalKeyboardKey.arrowRight:
        _horizontal(true);
      case LogicalKeyboardKey.arrowLeft:
        _horizontal(false);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _openCursor();
      case _:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Offers what [row] can do and carries out what was picked.
  Future<void> _menu(
    ProjectRow row,
    Offset at,
    EntryStatus status,
    WorkingFile? change,
  ) async {
    final items = projectMenuItems(
      isDir: row is ProjectDirRow,
      status: status,
      change: change,
    );
    final picked = await showContextMenu<ProjectMenuItem>(
      context: context,
      position: at,
      items: [
        for (final item in items)
          PopupMenuItem(
            value: item,
            height: 34,
            child: Text(_menuLabel(item), style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final actions = ref.read(repoActionsProvider(repoPath));
    switch (picked) {
      case ProjectMenuItem.newFile:
        await _create(row.path, dir: false);
      case ProjectMenuItem.newFolder:
        await _create(row.path, dir: true);
      case ProjectMenuItem.rename:
        await _rename(row);
      case ProjectMenuItem.delete:
        await _delete(row);
      case ProjectMenuItem.stage:
        await actions.stageFile(row.path);
      case ProjectMenuItem.unstage:
        await actions.unstageFile(row.path);
      case ProjectMenuItem.discard:
        await _discard(change!);
      case ProjectMenuItem.history:
        _showHistory(row.path);
      case ProjectMenuItem.reveal:
        await _reveal(row.path);
    }
  }

  /// Hands the file to the graph: the search filters on it, and the tab goes
  /// back to history so the result is what the user is looking at.
  void _showHistory(String path) {
    final query = ref.read(searchQueryProvider) ?? const CommitQuery();
    ref.read(searchQueryProvider.notifier).state = query.copyWith(path: path);
    final tab = ref.read(workspaceProvider).activeTab;
    if (tab != null) {
      ref
          .read(workspaceProvider.notifier)
          .setViewMode(tab.id, RepoViewMode.graph);
    }
  }

  /// Offers what the project root can do, for a click that landed on no row.
  Future<void> _rootMenu(Offset at) async {
    final picked = await showContextMenu<ProjectMenuItem>(
      context: context,
      position: at,
      items: [
        for (final item in projectRootMenuItems())
          PopupMenuItem(
            value: item,
            height: 34,
            child: Text(_menuLabel(item), style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case ProjectMenuItem.newFile:
        await _create('', dir: false);
      case ProjectMenuItem.newFolder:
        await _create('', dir: true);
      case ProjectMenuItem.reveal:
        await _reveal('');
      case _:
        break;
    }
  }

  static String _menuLabel(ProjectMenuItem item) => switch (item) {
    ProjectMenuItem.newFile => 'New file…',
    ProjectMenuItem.newFolder => 'New folder…',
    ProjectMenuItem.rename => 'Rename…',
    ProjectMenuItem.delete => 'Delete…',
    ProjectMenuItem.stage => 'Stage',
    ProjectMenuItem.unstage => 'Unstage',
    ProjectMenuItem.discard => 'Discard changes…',
    ProjectMenuItem.history => 'Show history',
    ProjectMenuItem.reveal => switch (Platform.operatingSystem) {
      'macos' => 'Reveal in Finder',
      'windows' => 'Show in Explorer',
      _ => 'Open containing folder',
    },
  };

  Future<void> _create(String relDir, {required bool dir}) async {
    final name = await showInputDialog(
      context,
      title: dir ? 'New folder' : 'New file',
      label: 'Name',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    final ops = ref.read(projectOpsProvider(repoPath));
    final r = await (dir
        ? ops.createFolder(relDir, name)
        : ops.createFile(relDir, name));
    if (!_report(r)) return;
    _reload(relDir);
    // The root is always shown; only a folder needs opening to reveal what
    // was just put in it.
    if (relDir.isNotEmpty) _setExpanded(relDir, true);
    ref.read(navCursorProvider(repoPath).notifier).state = r.path;
    // A new file is what the user meant to start writing in; a new folder has
    // nothing to show.
    if (!dir) _open(r.path!);
  }

  Future<void> _rename(ProjectRow row) async {
    final name = await showInputDialog(
      context,
      title: 'Rename',
      label: 'New name',
      initial: _basename(row.path),
      confirmLabel: 'Rename',
    );
    if (name == null || !mounted) return;
    final r = await ref
        .read(projectOpsProvider(repoPath))
        .rename(row.path, name);
    if (!_report(r)) return;
    final to = r.path!;
    ref.read(openFilesProvider(repoPath).notifier).rename(row.path, to);
    if (row is ProjectDirRow) _forgetExpanded(row.path);
    _reload(_parentOf(row.path));
    ref.read(navCursorProvider(repoPath).notifier).state = to;
  }

  Future<void> _delete(ProjectRow row) async {
    final ok = await confirmDestructive(
      ref,
      context,
      title: 'Delete ${_basename(row.path)}?',
      body: row is ProjectDirRow
          ? 'The folder and everything in it is removed from disk, not just '
                'from git.'
          : 'The file is removed from disk, not just from git.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    final r = await ref.read(projectOpsProvider(repoPath)).delete(row.path);
    if (!_report(r)) return;
    // An editor showing it keeps its text but stops being able to save it.
    ref.read(openFilesProvider(repoPath).notifier).markGone(row.path);
    if (row is ProjectDirRow) _forgetExpanded(row.path);
    _reload(_parentOf(row.path));
  }

  Future<void> _discard(WorkingFile change) async {
    final ok = await confirmDestructive(
      ref,
      context,
      title: 'Discard changes to ${_basename(change.path)}?',
      body: change.isUntracked
          ? 'The file is untracked, so discarding deletes it.'
          : 'The file goes back to what it was at the last commit.',
      confirmLabel: 'Discard',
    );
    if (!ok) return;
    await ref.read(repoActionsProvider(repoPath)).discardFile(change);
  }

  Future<void> _reveal(String relPath) async {
    try {
      await revealInFileManager(
        relPath.isEmpty ? repoPath : '$repoPath/$relPath',
      );
    } on ProcessException catch (e) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('Could not open the file manager', description: e.message);
    }
  }

  /// Reports a refusal and says whether the operation went through.
  bool _report(ProjectOpResult r) {
    if (r.ok) return true;
    ref
        .read(toastProvider.notifier)
        .show(r.error ?? 'Operation failed', kind: ToastKind.error);
    return false;
  }

  /// Re-reads one directory, so the tree shows what was just done to it
  /// without waiting for the filesystem watcher.
  void _reload(String relDir) =>
      ref.invalidate(dirListingProvider(DirKey(repoPath, relDir)));

  /// Drops a directory and everything under it from the opened set: after a
  /// rename or a delete those paths no longer name anything.
  void _forgetExpanded(String relDir) {
    final set = {...ref.read(expandedDirsProvider(repoPath))}
      ..removeWhere((p) => p == relDir || p.startsWith('$relDir/'));
    ref.read(expandedDirsProvider(repoPath).notifier).state = set;
  }

  static String _basename(String relPath) {
    final cut = relPath.lastIndexOf('/');
    return cut < 0 ? relPath : relPath.substring(cut + 1);
  }

  static String _parentOf(String relPath) {
    final cut = relPath.lastIndexOf('/');
    return cut < 0 ? '' : relPath.substring(0, cut);
  }

  /// Clicking is also a cursor move, so the arrows carry on from wherever the
  /// mouse left off.
  void _cursorTo(String path) {
    _focus.requestFocus();
    ref.read(navCursorProvider(repoPath).notifier).state = path;
  }

  Widget _row(
    AppTokens t,
    ProjectRow row,
    String? selected,
    String? cursor,
    EntryStatus Function(String path) statusOf,
    Map<String, WorkingFile> working,
  ) => switch (row) {
    ProjectDirRow() => _DirRow(
      row: row,
      // Git tracks files, not directories, so a folder only ever reports
      // whether an ignore rule covers it.
      ignored: statusOf(row.path) == EntryStatus.ignored,
      onCursor: row.path == cursor,
      onTap: () {
        _cursorTo(row.path);
        _setExpanded(row.path, !row.open);
      },
      onMenu: (at) {
        _cursorTo(row.path);
        _menu(row, at, statusOf(row.path), null);
      },
    ),
    ProjectFileRow() => _FileRow(
      row: row,
      status: statusOf(row.path),
      selected: row.path == selected,
      onCursor: row.path == cursor,
      onTap: () {
        _cursorTo(row.path);
        _open(row.path);
      },
      onMenu: (at) {
        _cursorTo(row.path);
        _menu(row, at, statusOf(row.path), working[row.path]);
      },
    ),
    ProjectLoadingRow() => Padding(
      padding: EdgeInsets.fromLTRB(FileTreeView.indent(row.depth), 6, 10, 6),
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent),
      ),
    ),
    ProjectMoreRow() => _NoteRow(depth: row.depth, text: '…${row.count} more'),
    ProjectErrorRow() => _NoteRow(depth: row.depth, text: row.message),
  };
}

class _Header extends StatelessWidget {
  final String repoPath;
  final bool hideIgnored;
  final VoidCallback onToggleIgnored;
  final VoidCallback onRefresh;
  final VoidCallback? onCollapse;
  const _Header({
    required this.repoPath,
    required this.hideIgnored,
    required this.onToggleIgnored,
    required this.onRefresh,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = repoPath
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty)
        .lastOrNull;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name ?? 'Project',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _MiniButton(
            icon: hideIgnored
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            tooltip: hideIgnored ? 'Show ignored files' : 'Hide ignored files',
            onTap: onToggleIgnored,
          ),
          _MiniButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onTap: onRefresh,
          ),
          if (onCollapse != null)
            _MiniButton(
              icon: Icons.chevron_left,
              tooltip: 'Collapse',
              onTap: onCollapse!,
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: t.textMuted),
        ),
      ),
    );
  }
}

class _DirRow extends StatelessWidget {
  final ProjectDirRow row;
  final bool ignored;

  /// The keyboard cursor is on this row.
  final bool onCursor;
  final VoidCallback onTap;
  final void Function(Offset at) onMenu;
  const _DirRow({
    required this.row,
    required this.onTap,
    required this.onMenu,
    this.ignored = false,
    this.onCursor = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: t.hover,
        child: Container(
          color: onCursor ? t.hover : Colors.transparent,
          padding: EdgeInsets.fromLTRB(
            FileTreeView.indent(row.depth),
            3,
            10,
            3,
          ),
          child: Row(
            children: [
              Icon(
                row.open ? Icons.expand_more : Icons.chevron_right,
                size: 15,
                color: t.textFaint,
              ),
              const SizedBox(width: 2),
              Icon(
                row.open ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 13,
                color: t.textFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ignored ? t.textFaint : t.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final ProjectFileRow row;
  final EntryStatus status;
  final bool selected;

  /// The keyboard cursor is on this row.
  final bool onCursor;
  final VoidCallback onTap;
  final void Function(Offset at) onMenu;
  const _FileRow({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    this.status = EntryStatus.unknown,
    this.onCursor = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: t.hover,
        child: Container(
          color: selected
              ? t.active
              : (onCursor ? t.hover : Colors.transparent),
          padding: EdgeInsets.fromLTRB(
            FileTreeView.indent(row.depth) + 17,
            3,
            10,
            3,
          ),
          child: Row(
            children: [
              Icon(
                row.isLink ? Icons.link : Icons.insert_drive_file_outlined,
                size: 13,
                color: t.textFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: switch (status) {
                      EntryStatus.ignored => t.textFaint,
                      _ => selected ? t.textPrimary : t.textMuted,
                    },
                    fontSize: 12,
                  ),
                ),
              ),
              if (_badge(status) case final badge?) ...[
                const SizedBox(width: 6),
                Text(
                  badge,
                  style: TextStyle(
                    color: status == EntryStatus.modified
                        ? t.warning
                        : t.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The one-letter mark the working-tree panel already uses for the same
  /// states. Clean, ignored and unknown entries carry none.
  static String? _badge(EntryStatus status) => switch (status) {
    EntryStatus.modified => 'M',
    EntryStatus.untracked => 'U',
    _ => null,
  };
}

/// A non-interactive row: a truncation notice or a listing error.
class _NoteRow extends StatelessWidget {
  final int depth;
  final String text;
  const _NoteRow({required this.depth, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(FileTreeView.indent(depth) + 17, 4, 10, 4),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.textFaint,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
