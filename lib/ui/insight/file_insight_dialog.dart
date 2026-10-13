import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/blame.dart';
import '../../domain/text_tabs.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/compare_target.dart';
import '../../state/diff_target.dart';
import '../../state/file_insight.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'line_history_dialog.dart';

/// File History / Blame modal with two tabs. History rows open the file's diff
/// at that commit; Blame annotates each line with its last-touching commit.
/// Read as of [rev] when given — and titled so — else the working tree / HEAD.
Future<void> showFileInsight(
  BuildContext context, {
  required String repoPath,
  required String path,
  int initialTab = 0,
  String? rev,
}) => showAppModal<void>(
  context: context,
  title: fileInsightTitle(path, rev),
  icon: Icons.history,
  width: 720,
  body: SizedBox(
    height: 480,
    child: _InsightBody(
      repoPath: repoPath,
      path: path,
      initialTab: initialTab,
      rev: rev,
    ),
  ),
);

/// The dialog title: the path, and the revision it is read at when that is
/// not the checkout.
String fileInsightTitle(String path, String? rev) =>
    rev == null ? path : '$path @ ${compareRefLabel(rev)}';

class _InsightBody extends StatelessWidget {
  final String repoPath;
  final String path;
  final int initialTab;
  final String? rev;
  const _InsightBody({
    required this.repoPath,
    required this.path,
    required this.initialTab,
    this.rev,
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
                _HistoryTab(repoPath: repoPath, path: path, rev: rev),
                _BlameTab(repoPath: repoPath, path: path, rev: rev),
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
  final String? rev;
  const _HistoryTab({required this.repoPath, required this.path, this.rev});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final dateFormat = ref.watch(settingsProvider.select((s) => s.dateFormat));
    return ref
        .watch(fileHistoryProvider((repo: repoPath, path: path, rev: rev)))
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
                            style: AppFonts.mns(size: 11.5, color: t.textFaint),
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
  final String? rev;
  const _BlameTab({required this.repoPath, required this.path, this.rev});

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
            rev: widget.rev ?? 'HEAD',
          ),
          child: Text(l.lhLineHistory, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: _BlameOptionsMenu(repoPath: widget.repoPath),
      ),
      Expanded(child: _lines(context)),
    ],
  );

  Widget _lines(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(
          blameProvider((
            repo: widget.repoPath,
            path: widget.path,
            rev: widget.rev,
          )),
        )
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
                          style: AppFonts.mns(size: 11, color: t.accent),
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
                          expandTabs(line.content),
                          style: AppFonts.mns(size: 12, color: t.textMuted),
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

/// The blame tab's options: whitespace, moved lines, and — when the
/// repository has one — whether to see past the commits its ignore-revs file
/// lists. The icon is lit whenever blame reads differently from plain git, so
/// a line credited past a commit is never a silent surprise.
class _BlameOptionsMenu extends ConsumerWidget {
  final String repoPath;
  const _BlameOptionsMenu({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final options = ref.watch(blameOptionsProvider);
    final revsFile = ref.watch(blameIgnoreRevsProvider(repoPath)).valueOrNull;
    void set(BlameOptions next) =>
        ref.read(blameOptionsProvider.notifier).state = next;
    // Skipping is on by default, so only switching it off reads differently,
    // and only where there is a file to switch off.
    final active =
        options.ignoreWhitespace ||
        options.moves != BlameMoves.off ||
        (revsFile != null && !options.skipIgnoredRevs);
    return PopupMenuButton<VoidCallback>(
      tooltip: l.boOptions,
      iconSize: 18,
      icon: Icon(Icons.tune, color: active ? t.accent : null),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: () => set(
            options.copyWith(ignoreWhitespace: !options.ignoreWhitespace),
          ),
          checked: options.ignoreWhitespace,
          child: Text(l.boIgnoreWhitespace),
        ),
        const PopupMenuDivider(),
        for (final (moves, label) in [
          (BlameMoves.off, l.boMovesOff),
          (BlameMoves.withinFile, l.boMovesWithinFile),
          (BlameMoves.acrossFiles, l.boMovesAcrossFiles),
        ])
          CheckedPopupMenuItem(
            value: () => set(options.copyWith(moves: moves)),
            checked: options.moves == moves,
            child: Text(label),
          ),
        if (revsFile != null) ...[
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: () => set(
              options.copyWith(skipIgnoredRevs: !options.skipIgnoredRevs),
            ),
            checked: options.skipIgnoredRevs,
            child: Tooltip(
              message: revsFile,
              child: Text(l.boSkipRevs(p.basename(revsFile))),
            ),
          ),
        ],
      ],
    );
  }
}
