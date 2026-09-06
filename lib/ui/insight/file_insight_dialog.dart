import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/file_insight.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'line_history_dialog.dart';

/// File History / Blame modal with two tabs. History rows open the file's diff
/// at that commit; Blame annotates each line with its last-touching commit.
Future<void> showFileInsight(
  BuildContext context, {
  required String repoPath,
  required String path,
  int initialTab = 0,
}) => showAppModal<void>(
  context: context,
  title: path,
  icon: Icons.history,
  width: 720,
  body: SizedBox(
    height: 480,
    child: _InsightBody(repoPath: repoPath, path: path, initialTab: initialTab),
  ),
);

class _InsightBody extends StatelessWidget {
  final String repoPath;
  final String path;
  final int initialTab;
  const _InsightBody({
    required this.repoPath,
    required this.path,
    required this.initialTab,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Column(
        children: [
          TabBar(
            labelColor: t.textPrimary,
            unselectedLabelColor: t.textFaint,
            indicatorColor: t.accent,
            tabs: [
              Tab(text: l.fiHistory),
              Tab(text: l.wtpBlame),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _HistoryTab(repoPath: repoPath, path: path),
                _BlameTab(repoPath: repoPath, path: path),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  final String repoPath;
  final String path;
  const _HistoryTab({required this.repoPath, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final dateFormat = ref.watch(settingsProvider.select((s) => s.dateFormat));
    return ref
        .watch(fileHistoryProvider((repo: repoPath, path: path)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(l.fiCouldNotLoad, style: TextStyle(color: t.textMuted)),
          ),
          data: (commits) => ListView(
            children: [
              for (final c in commits)
                InkWell(
                  onTap: () {
                    ref.read(diffTargetProvider.notifier).state = DiffTarget(
                      repoPath: repoPath,
                      path: path,
                      commitSha: c.sha,
                    );
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(
                            c.shortSha,
                            style: TextStyle(
                              color: t.textFaint,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            c.message,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${c.author} · '
                          '${formatCommitDate(c.date, format: dateFormat)}',
                          style: TextStyle(color: t.textFaint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
  }
}

/// Blame rows, each annotated with the commit that last touched the line.
///
/// Rows pick out a run the way a text editor does — click to set one end,
/// shift-click the other — and the run is what Line history asks about. The
/// selection lives here rather than in a provider: it means nothing once the
/// dialog closes.
class _BlameTab extends ConsumerStatefulWidget {
  final String repoPath;
  final String path;
  const _BlameTab({required this.repoPath, required this.path});

  @override
  ConsumerState<_BlameTab> createState() => _BlameTabState();
}

class _BlameTabState extends ConsumerState<_BlameTab> {
  /// Row indices, not line numbers: the ends of the picked run, in the order
  /// they were clicked. Null when nothing is picked.
  int? _anchor;
  int? _focus;

  int get _start => (_anchor! < _focus! ? _anchor : _focus)!;
  int get _end => (_anchor! > _focus! ? _anchor : _focus)!;
  bool _selected(int i) => _anchor != null && i >= _start && i <= _end;

  void _select(int anchor, int focus) => setState(() {
    _anchor = anchor;
    _focus = focus;
  });

  /// A left-click: shift extends from the end already anchored, a plain click
  /// starts a fresh run.
  void _pick(int i) =>
      HardwareKeyboard.instance.isShiftPressed && _anchor != null
      ? _select(_anchor!, i)
      : _select(i, i);

  Future<void> _menu(Offset at, int i) async {
    // A right-click away from the run moves the run onto it, so the menu always
    // acts on the row it opened over — shift included, since the user never
    // dragged out the run it would otherwise extend.
    if (!_selected(i)) _select(i, i);
    final l = AppLocalizations.of(context);
    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () => showLineHistory(
            context,
            repoPath: widget.repoPath,
            path: widget.path,
            // Blame numbers lines from one; row indices start at zero.
            start: _start + 1,
            end: _end + 1,
          ),
          child: Text(l.lhLineHistory, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(blameProvider((repo: widget.repoPath, path: widget.path)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              l.fiCouldNotBlame,
              style: TextStyle(color: t.textMuted),
            ),
          ),
          data: (lines) => ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final line = lines[i];
              final newBlock = i == 0 || lines[i - 1].sha != line.sha;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(i),
                onSecondaryTapUp: (d) => _menu(d.globalPosition, i),
                child: Container(
                  color: _selected(i)
                      ? t.accent.withValues(alpha: 0.18)
                      : (newBlock ? t.bgPanel : null),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 1,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 66,
                        child: Text(
                          newBlock ? line.shortSha : '',
                          style: TextStyle(
                            color: t.accent,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: Text(
                          newBlock ? line.author : '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.textFaint, fontSize: 11),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: t.textFaint, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line.content,
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
  }
}
