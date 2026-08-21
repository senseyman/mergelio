import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/commit_message.dart';
import '../../domain/git/models.dart';
import '../../domain/git/rebase_plan.dart';
import '../../domain/search.dart';
import '../../state/content_search.dart';
import '../../state/graph_selection.dart';
import '../../state/path_history.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/search.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../rebase/rebase_editor.dart';
import '../shell/remote_merge_confirm.dart';
import '../shell/repo_op_dialogs.dart';
import '../shell/resize_handle.dart';
import '../workspace/branch_switch.dart';
import '../workspace/edit_commit_message.dart';
import '../../l10n/gen/app_localizations.dart';
import 'commit_columns.dart';
import 'graph_derived.dart';
import 'commit_row.dart';
import 'rail_metrics.dart';
import 'squash_overlay.dart';

/// Centre panel: the commit graph for the active repo. Loads [RepoData] and
/// hands it to [GraphList]; shows nothing when no repo tab is active.
class GraphView extends ConsumerWidget {
  const GraphView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final path = ref.watch(workspaceProvider.select((w) => w.activeTab?.path));
    if (path == null) return Container(color: t.bgApp);

    return Container(
      color: t.bgApp,
      child: ref
          .watch(repoDataProvider(path))
          .when(
            loading: () => const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                'Could not read repository',
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            data: (d) => GraphList(data: d),
          ),
    );
  }
}

/// The graph itself: header with the Columns menu, then a virtualised list of
/// fixed-height rows — a WIP row on top when the working tree is dirty,
/// followed by the commits. Arrow keys move the selection and keep it visible.
class GraphList extends ConsumerStatefulWidget {
  final RepoData data;
  const GraphList({super.key, required this.data});

  @override
  ConsumerState<GraphList> createState() => _GraphListState();
}

class _GraphListState extends ConsumerState<GraphList> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'graph');

  // Memoized graph derivations + search matches, recomputed only when their
  // inputs change (the RepoData object, or the query), never on every rebuild.
  RepoData? _derivedFor;
  GraphDerived? _derived;
  RepoData? _matchDataFor;
  CommitQuery? _matchQueryFor;
  Set<String>? _matchPathsFor;
  Set<String>? _matchContentFor;
  Set<String> _matchCache = const {};

  GraphDerived _deriveFor(RepoData d) {
    if (!identical(_derivedFor, d) || _derived == null) {
      _derived = computeGraphDerived(d);
      _derivedFor = d;
    }
    return _derived!;
  }

  int _matchGen = 0;

  /// Current match set. Small histories compute inline; big ones kick a
  /// background-isolate computation and keep showing the previous set until
  /// it lands (generation counter drops stale results).
  Set<String> _matchesFor(
    RepoData d,
    CommitQuery? query,
    Set<String>? paths,
    Set<String>? content,
  ) {
    if (query == null || query.isEmpty) return const {};
    if (identical(_matchDataFor, d) &&
        query == _matchQueryFor &&
        identical(_matchPathsFor, paths) &&
        identical(_matchContentFor, content)) {
      return _matchCache;
    }
    _matchDataFor = d;
    _matchQueryFor = query;
    _matchPathsFor = paths;
    _matchContentFor = content;
    // Bump the generation on every recompute so any still-in-flight isolate
    // result from a previous (data, query) is dropped when it lands.
    final gen = ++_matchGen;
    if (d.commits.length < searchIsolateThreshold) {
      _matchCache = {
        for (final c in d.commits)
          if (matchesCommit(c, query, pathShas: paths, contentShas: content))
            c.sha,
      };
      return _matchCache;
    }
    computeMatchShas(
      d.commits,
      query,
      pathShas: paths,
      contentShas: content,
    ).then((m) {
      if (mounted && gen == _matchGen) setState(() => _matchCache = m);
    });
    return _matchCache;
  }

  // 1-based ordinal of each matched sha in commit order, memoized by the match
  // set identity so the search "x / y" counter doesn't rescan on every build.
  Set<String>? _ordinalsFor;
  Map<String, int> _ordinals = const {};

  Map<String, int> _matchOrdinals(RepoData d, Set<String> matches) {
    if (identical(_ordinalsFor, matches)) return _ordinals;
    final m = <String, int>{};
    var i = 0;
    for (final c in d.commits) {
      if (matches.contains(c.sha)) m[c.sha] = ++i;
    }
    _ordinals = m;
    _ordinalsFor = matches;
    return _ordinals;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasWip => widget.data.working.isNotEmpty;

  // Cached squash-dash geometry, rebuilt only when the segments or metrics
  // change — not on every scroll frame.
  List<SquashSegment>? _dashesForSegments;
  bool? _dashesCompact;
  List<SquashDash> _dashes = const [];

  List<SquashDash> _dashesFor(
    List<SquashSegment> segments,
    RailMetrics metrics,
    int wipRows,
    List<Color> palette,
  ) {
    if (identical(_dashesForSegments, segments) &&
        _dashesCompact == metrics.compact) {
      return _dashes;
    }
    _dashes = buildSquashDashes(segments, metrics, wipRows, palette);
    _dashesForSegments = segments;
    _dashesCompact = metrics.compact;
    return _dashes;
  }

  void _select(String id, double rowHeight) {
    // Scrolling is handled centrally by the selectedCommit listener, so a
    // selection from anywhere (this list, the sidebar, the palette) flies to
    // the row the same way.
    ref.read(selectedCommitProvider.notifier).state = id;
  }

  /// Brings the row for [sha] into view if it is off-screen. Uses the memoized
  /// sha→index map (O(1)) rather than scanning the commit list, so clicking a
  /// branch on a 50k-commit repo flies instantly. No-op when the sha isn't a
  /// loaded commit (e.g. a branch tip beyond the commit cap).
  void _scrollToSha(String? sha, double rowHeight) {
    if (sha == null || !_scroll.hasClients) return;
    final wipRows = _hasWip ? 1 : 0;
    final int i;
    if (sha == wipSelection) {
      i = 0;
    } else {
      final ci = _deriveFor(widget.data).rowIndex[sha];
      if (ci == null) return;
      i = ci + wipRows;
    }
    final top = i * rowHeight;
    final viewTop = _scroll.offset;
    final viewBottom = viewTop + _scroll.position.viewportDimension;
    if (top < viewTop) {
      _scroll.animateTo(
        top,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else if (top + rowHeight > viewBottom) {
      _scroll.animateTo(
        top + rowHeight - _scroll.position.viewportDimension,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  /// Selects and flies to the next/previous search match relative to the
  /// current selection.
  void _jumpMatch(
    RepoData d,
    Set<String> matches,
    bool forward,
    RailMetrics metrics,
  ) {
    if (matches.isEmpty) return;
    final ordered = [
      for (final c in d.commits)
        if (matches.contains(c.sha)) c.sha,
    ];
    final current = ref.read(selectedCommitProvider);
    final at = current == null ? -1 : ordered.indexOf(current);
    final next = forward
        ? (at + 1) % ordered.length
        : (at - 1 + ordered.length) % ordered.length;
    _select(ordered[next], metrics.rowHeight);
  }

  /// Merge/Rebase menu for a branch dropped onto a commit's local ref.
  Future<void> _branchDropMenu(
    BuildContext context,
    String source,
    String target,
    Offset at,
  ) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        PopupMenuItem(
          height: 34,
          onTap: () async {
            if (await confirmRemoteSource(
              context,
              ref,
              repoPath: path,
              source: source,
            )) {
              await actions.mergeInto(source, target);
            }
          },
          child: Text(
            'Merge «$source» into «$target»',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        PopupMenuItem(
          height: 34,
          onTap: () => actions.rebaseOnto(source, target),
          child: Text(
            'Rebase «$source» onto «$target»',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, double rowHeight) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // N / ⇧N step through search matches while a search is active and the
    // graph (not the search field) has focus.
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      final query = ref.read(searchQueryProvider);
      if (query != null && !query.isEmpty) {
        // Reuses whatever the last build computed, path and content shas
        // included.
        final matches = _matchesFor(
          widget.data,
          query,
          _matchPathsFor,
          _matchContentFor,
        );
        _jumpMatch(
          widget.data,
          matches,
          !HardwareKeyboard.instance.isShiftPressed,
          RailMetrics(compact: ref.read(settingsProvider).graphCompact),
        );
        return KeyEventResult.handled;
      }
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    // Row math via the memoized index map instead of building the full order
    // list + indexOf on every keypress.
    final d = widget.data;
    final wipRows = _hasWip ? 1 : 0;
    final total = d.commits.length + wipRows;
    if (total == 0) return KeyEventResult.ignored;
    final current = ref.read(selectedCommitProvider);
    final int i;
    if (current == null) {
      i = -1;
    } else if (current == wipSelection) {
      i = 0;
    } else {
      final ci = _deriveFor(d).rowIndex[current];
      i = ci == null ? -1 : ci + wipRows;
    }
    final next = (i + delta).clamp(0, total - 1);
    _select(_shaAtRow(next, wipRows), rowHeight);
    return KeyEventResult.handled;
  }

  /// Sha at visible row [row] (WIP row first when present).
  String _shaAtRow(int row, int wipRows) => (_hasWip && row == 0)
      ? wipSelection
      : widget.data.commits[row - wipRows].sha;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final compact = ref.watch(settingsProvider.select((s) => s.graphCompact));
    final cols = ref.watch(settingsProvider.select((s) => s.graphCols));
    final dateFormat = ref.watch(settingsProvider.select((s) => s.dateFormat));
    final branchWidth = ref.watch(
      settingsProvider.select((s) => s.graphBranchWidth),
    );
    final railWidth = ref.watch(
      settingsProvider.select((s) => s.graphRailWidth),
    );
    final selected = ref.watch(selectedCommitProvider);
    final metrics = RailMetrics(
      compact: compact,
      branchWidth: branchWidth,
      railFixedWidth: railWidth,
    );

    // Fly to the selected commit whenever the selection changes — from the
    // graph, the sidebar branch rows, or the command palette. Deferred a frame
    // so the ListView has its dimensions when a selection arrives on load.
    ref.listen(selectedCommitProvider, (_, sha) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToSha(sha, metrics.rowHeight),
      );
    });

    final derived = _deriveFor(d);
    final maxLane = derived.maxLane;
    final labels = derived.labels;
    final segments = derived.segments;
    final stashBySha = {for (final s in d.stashes) s.sha: s.ref};

    final wipRows = _hasWip ? 1 : 0;

    final query = ref.watch(searchQueryProvider);
    // The commits that touched the followed file, if one is being followed.
    // Only the loaded value counts: while the read is in flight the filter has
    // no shas yet and the graph shows no matches.
    final repo = ref.watch(workspaceProvider.select((w) => w.activeTab?.path));
    final pathShas = (query == null || query.path.isEmpty || repo == null)
        ? null
        : ref.watch(pathHistoryProvider(PathKey(repo, query.path))).valueOrNull;
    // The commits whose diff matched the pickaxe string, on the same terms:
    // until the read lands there are no shas and so no matches, and the search
    // bar says so rather than reporting a false "no matches".
    final content = (query == null || query.content.isEmpty || repo == null)
        ? null
        : ref.watch(
            contentSearchProvider(
              ContentKey(repo, query.content, query.contentMode),
            ),
          );
    final matchShas = _matchesFor(d, query, pathShas, content?.valueOrNull);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (query != null)
          _SearchBar(
            query: query,
            matchCount: matchShas.length,
            searching: content?.isLoading ?? false,
            currentIndex: () {
              // Position of the selected commit among ordered matches, 1-based.
              // Uses a memoized ordinal map so this is O(1) per keystroke rather
              // than an O(commits) scan.
              if (selected == null) return 0;
              return _matchOrdinals(d, matchShas)[selected] ?? 0;
            }(),
            onChanged: (q) => ref.read(searchQueryProvider.notifier).state = q,
            onClose: () => ref.read(searchQueryProvider.notifier).state = null,
            onJump: (forward) => _jumpMatch(d, matchShas, forward, metrics),
          )
        else
          _GraphHeader(cols: cols, compact: compact),
        Expanded(
          child: Focus(
            focusNode: _focus,
            onKeyEvent: (n, e) => _onKey(n, e, metrics.rowHeight),
            child: GestureDetector(
              onTap: _focus.requestFocus,
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scroll,
                    itemExtent: metrics.rowHeight,
                    itemCount: d.commits.length + wipRows,
                    itemBuilder: (context, i) {
                      if (_hasWip && i == 0) {
                        return _WipRow(
                          metrics: metrics,
                          maxLane: maxLane,
                          branchColumn: cols['branch'] ?? true,
                          fileCount: d.working.length,
                          selected: selected == wipSelection,
                          onTap: () {
                            _focus.requestFocus();
                            _select(wipSelection, metrics.rowHeight);
                          },
                        );
                      }
                      final ci = i - wipRows;
                      final c = d.commits[ci];
                      // Name a branch only on the top row of its contiguous run:
                      // when this row's label differs from the row directly
                      // above it (or it is the first commit).
                      final rowLabels = labels[c.sha] ?? const <String>[];
                      final prevLabels = ci > 0
                          ? (labels[d.commits[ci - 1].sha] ?? const <String>[])
                          : const <String>[];
                      final row = _CommitContextMenu(
                        commit: c,
                        child: CommitRow(
                          commit: c,
                          branchLabels: rowLabels,
                          showBranchLabel:
                              rowLabels.isNotEmpty &&
                              !listEquals(rowLabels, prevLabels),
                          metrics: metrics,
                          maxLane: maxLane,
                          cols: cols,
                          dateFormat: dateFormat,
                          stashLabel: stashBySha[c.sha],
                          selected: selected == c.sha,
                          searchMatch: query == null || query.isEmpty
                              ? null
                              : matchShas.contains(c.sha),
                          onTap: () {
                            _focus.requestFocus();
                            _select(c.sha, metrics.rowHeight);
                          },
                          onBranchActivated: (label) {
                            final repoPath = ref
                                .read(workspaceProvider)
                                .activeTab
                                ?.path;
                            if (repoPath == null) return;
                            final target = resolveBranchChip(
                              label,
                              d.remoteBranches,
                            );
                            // Double-clicking the current branch is a no-op.
                            if (target.local != null &&
                                d.branches.any(
                                  (b) => b.current && b.name == target.local,
                                )) {
                              return;
                            }
                            activateBranch(
                              ref,
                              context,
                              repoPath,
                              localBranch: target.local,
                              remote: target.remote,
                            );
                          },
                        ),
                      );
                      // A commit carrying a local branch ref accepts a branch
                      // drag from the sidebar, opening the Merge/Rebase menu
                      // against that branch (same flow as branch-onto-branch).
                      final localRef = derived.localRefBySha[c.sha];
                      if (localRef == null) return row;
                      return DragTarget<String>(
                        onWillAcceptWithDetails: (dd) => dd.data != localRef,
                        onAcceptWithDetails: (dd) => _branchDropMenu(
                          context,
                          dd.data,
                          localRef,
                          dd.offset,
                        ),
                        builder: (ctx, candidates, _) => Container(
                          color: candidates.isNotEmpty
                              ? context.tokens.accent.withValues(alpha: 0.14)
                              : null,
                          child: row,
                        ),
                      );
                    },
                  ),
                  if (segments.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: SquashDashPainter(
                              dashes: _dashesFor(
                                segments,
                                metrics,
                                wipRows,
                                context.tokens.branchPalette,
                              ),
                              scroll: _scroll,
                              // Rail is shifted right by the branch gutter when
                              // that column is on, so the overlay shifts with it.
                              dx: (cols['branch'] ?? true)
                                  ? metrics.branchWidth
                                  : 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Draggable column dividers, overlaid full-height at the
                  // branch|rail and rail|description boundaries. Dragging the
                  // rail handle seeds from the current rail width so it grows
                  // past the auto-size floor immediately.
                  ...() {
                    final branchOn = cols['branch'] ?? true;
                    final ctl = ref.read(settingsProvider.notifier);
                    final branchX = branchOn ? metrics.branchWidth : 0.0;
                    final railX = branchX + metrics.railWidth(maxLane);
                    return [
                      if (branchOn)
                        Positioned(
                          left: branchX - 3.5,
                          top: 0,
                          bottom: 0,
                          child: ResizeHandle(
                            onDrag: (dx) => ctl.setGraphBranchWidth(
                              metrics.branchWidth + dx,
                            ),
                            onReset: () => ctl.setGraphBranchWidth(116),
                          ),
                        ),
                      Positioned(
                        left: railX - 3.5,
                        top: 0,
                        bottom: 0,
                        child: ResizeHandle(
                          onDrag: (dx) => ctl.setGraphRailWidth(
                            metrics.railWidth(maxLane) + dx,
                          ),
                          onReset: () => ctl.setGraphRailWidth(0),
                        ),
                      ),
                    ];
                  }(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How long the content field waits for typing to stop before running the
/// pickaxe. Every run reads the whole history's diffs, so a git process per
/// keystroke would leave the machine doing nothing else.
const _contentDebounce = Duration(milliseconds: 350);

/// Global-search bar shown in place of the header while a search is open.
class _SearchBar extends StatefulWidget {
  final CommitQuery query;
  final int matchCount;

  /// True while the pickaxe is still running, so an empty result reads as
  /// "not finished yet" rather than "nothing found".
  final bool searching;
  // 1-based position of the selected match, 0 when the selection is not a
  // match. Rendered as "current / total".
  final int currentIndex;
  final ValueChanged<CommitQuery> onChanged;
  final VoidCallback onClose;
  final void Function(bool forward) onJump;
  const _SearchBar({
    required this.query,
    required this.matchCount,
    required this.searching,
    required this.currentIndex,
    required this.onChanged,
    required this.onClose,
    required this.onJump,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _setContent(String v) {
    _debounce?.cancel();
    widget.onChanged(widget.query.copyWith(content: v));
  }

  void _typedContent(String v) {
    _debounce?.cancel();
    _debounce = Timer(_contentDebounce, () => _setContent(v));
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final onChanged = widget.onChanged;
    final onClose = widget.onClose;
    final onJump = widget.onJump;
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final noMatches =
        !query.isEmpty && !widget.searching && widget.matchCount == 0;
    final regex = query.contentMode == ContentSearchMode.diffText;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: t.bgPanel,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 15, color: t.textFaint),
            const SizedBox(width: 8),
            // The two text fields share whatever the fixed filters leave, so a
            // graph panel narrower than a wide monitor shrinks them instead of
            // pushing the buttons off the bar.
            Expanded(
              flex: 3,
              child: TextField(
                autofocus: true,
                onChanged: (v) => onChanged(query.copyWith(text: v)),
                onSubmitted: (_) => onJump(true),
                style: TextStyle(color: t.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search commits…',
                  hintStyle: TextStyle(color: t.textFaint, fontSize: 13),
                ),
              ),
            ),
            // Content filter feeds CommitQuery.content: which commits' diffs
            // mention the string is read from git, not from the loaded
            // commits, so this is the only filter that can answer "which
            // commit introduced this?".
            Icon(Icons.code, size: 15, color: t.textFaint),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Tooltip(
                message: regex ? l.searchContentRegexHelp : l.searchContentHelp,
                child: TextField(
                  key: const ValueKey('search:content'),
                  onChanged: _typedContent,
                  onSubmitted: _setContent,
                  style: TextStyle(color: t.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l.searchContentHint,
                    hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
                    // The mode toggle rides inside the field it changes rather
                    // than beside it: as a fixed-width chip on the row it cost
                    // the bar enough width to overflow on a laptop.
                    suffixIconConstraints: const BoxConstraints(minWidth: 0),
                    suffixIcon: _RegexToggle(
                      on: regex,
                      label: l.filterContentRegex,
                      onTap: () => onChanged(
                        query.copyWith(
                          contentMode: regex
                              ? ContentSearchMode.occurrences
                              : ContentSearchMode.diffText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Author filter feeds CommitQuery.author.
            SizedBox(
              width: 120,
              child: TextField(
                onChanged: (v) => onChanged(query.copyWith(author: v)),
                style: TextStyle(color: t.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Author…',
                  hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
                ),
              ),
            ),
            if (query.path.isNotEmpty) ...[
              const SizedBox(width: 6),
              // Flexible so a narrow window shortens the name rather than
              // pushing the match counter and buttons off the bar.
              Flexible(
                child: _PathChip(
                  path: query.path,
                  onClear: () => onChanged(query.copyWith(path: '')),
                ),
              ),
            ],
            const SizedBox(width: 6),
            _FilterChip(
              label: l.filterHideMerges,
              on: query.hideMerges,
              onTap: () =>
                  onChanged(query.copyWith(hideMerges: !query.hideMerges)),
            ),
            const SizedBox(width: 6),
            _FilterChip(
              label: l.filterHideTags,
              on: query.hideTags,
              onTap: () => onChanged(query.copyWith(hideTags: !query.hideTags)),
            ),
            const SizedBox(width: 8),
            Text(
              widget.searching
                  ? l.searchRunning
                  : noMatches
                  ? l.searchNoMatches
                  : (widget.currentIndex > 0
                        ? '${widget.currentIndex} / ${widget.matchCount}'
                        : '${widget.matchCount}'),
              style: TextStyle(
                color: noMatches ? t.warning : t.textFaint,
                fontSize: 12,
              ),
            ),
            IconButton(
              iconSize: 16,
              tooltip: 'Previous (⇧N)',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => onJump(false),
            ),
            IconButton(
              iconSize: 16,
              tooltip: 'Next (N)',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => onJump(true),
            ),
            IconButton(
              iconSize: 16,
              tooltip: 'Close (Esc)',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// Switches the content search between counting occurrences of a literal
/// string and matching diff lines as a regular expression. Drawn as `.*`
/// inside the content field, lit when on.
class _RegexToggle extends StatelessWidget {
  final bool on;
  final String label;
  final VoidCallback onTap;
  const _RegexToggle({
    required this.on,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(
            '.*',
            style: TextStyle(
              color: on ? t.accent : t.textFaint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: on ? t.accent.withValues(alpha: 0.16) : null,
            border: Border.all(color: on ? Colors.transparent : t.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? t.accent : t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The file the history is being followed for. Named so it is obvious why the
/// graph is showing so few commits, and dismissible so the user is never stuck
/// wondering where the rest went.
class _PathChip extends StatelessWidget {
  final String path;
  final VoidCallback onClear;
  const _PathChip({required this.path, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = path.split('/').last;
    return Tooltip(
      message: path,
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 12, color: t.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: t.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // A plain tap target rather than an IconButton: the button's
            // 40px minimum would crowd the name out of the chip.
            InkWell(
              key: const ValueKey('search:clearPath'),
              onTap: onClear,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.close, size: 12, color: t.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphHeader extends ConsumerWidget {
  final Map<String, bool> cols;
  final bool compact;
  const _GraphHeader({required this.cols, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final ctl = ref.read(settingsProvider.notifier);
    const names = graphColumnLabels;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            l.graphHistory,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Columns',
            onSelected: (id) => id == 'compact'
                ? ctl.toggleGraphCompact()
                : ctl.toggleGraphCol(id),
            itemBuilder: (context) => [
              for (final e in names.entries)
                CheckedPopupMenuItem(
                  value: e.key,
                  checked: cols[e.key] ?? true,
                  height: 36,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)),
                ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'compact',
                checked: compact,
                height: 36,
                child: Text(
                  l.graphCompact,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Columns',
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  Icon(Icons.arrow_drop_down, size: 16, color: t.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uncommitted-changes row pinned above the newest commit: dashed amber node
/// and a summary of how many files changed. Disappears when the tree is clean.
class _WipRow extends StatelessWidget {
  final RailMetrics metrics;
  final int maxLane;
  final bool branchColumn;
  final int fileCount;
  final bool selected;
  final VoidCallback onTap;

  const _WipRow({
    required this.metrics,
    required this.maxLane,
    required this.branchColumn,
    required this.fileCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      hoverColor: t.hover,
      child: Container(
        height: metrics.rowHeight,
        color: selected ? t.active : null,
        child: Row(
          children: [
            // Empty gutter keeps the rail aligned with the commit rows below.
            if (branchColumn) SizedBox(width: metrics.branchWidth),
            ClipRect(
              child: SizedBox(
                width: metrics.railWidth(maxLane),
                child: CustomPaint(
                  size: Size(metrics.railWidth(maxLane), metrics.rowHeight),
                  painter: _WipRailPainter(m: metrics, color: t.warning),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'WIP',
                    style: TextStyle(
                      color: t.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Uncommitted changes · '
                      '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed ring at lane 0 with a strand continuing down to the commit below.
class _WipRailPainter extends CustomPainter {
  final RailMetrics m;
  final Color color;
  const _WipRailPainter({required this.m, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final x = m.laneX(0);
    final y = m.nodeY;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;

    canvas.drawLine(Offset(x, y), Offset(x, size.height), stroke);

    const dash = 4.0, gap = 3.0;
    final ring = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, y), radius: 7));
    for (final metric in ring.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), stroke);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_WipRailPainter old) =>
      old.color != color || old.m.compact != m.compact;
}

/// Right-click scaffold; every mutation lands in a later stage, Copy SHA works
/// now.
/// Per-commit right-click menu wired to real, undoable git operations.
class _CommitContextMenu extends ConsumerWidget {
  final Commit commit;
  final Widget child;
  const _CommitContextMenu({required this.commit, required this.child});

  Future<void> _open(BuildContext context, WidgetRef ref, Offset at) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    final sha = commit.sha;
    final l = AppLocalizations.of(context);

    PopupMenuItem<void> item(
      String label,
      VoidCallback onTap, {
      bool danger = false,
    }) => PopupMenuItem(
      height: 34,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: danger ? context.tokens.danger : null,
        ),
      ),
    );

    await showContextMenu<void>(
      context: context,
      position: at,
      items: [
        item(l.menuCheckout, () => actions.checkout(sha)),
        item(l.menuCreateBranch, () async {
          final name = await showInputDialog(
            context,
            title: 'Create branch',
            label: 'Branch name',
          );
          if (name != null) await actions.createBranch(name, at: sha);
        }),
        item(l.menuCreateTag, () => showTagDialog(context, ref, path, at: sha)),
        item(l.menuCherryPick, () => actions.cherryPick(sha)),
        item(l.menuRevert, () => actions.revert(sha)),
        item(l.menuRebaseHere, () async {
          final steps = await actions.rebaseStepsFrom(sha);
          if (steps.isEmpty) return;
          if (!context.mounted) return;
          final plan = await showRebaseEditor(context, steps: steps);
          if (plan == null || isNoOpPlan(steps, plan)) return; // unchanged
          await actions.rebase(sha, plan);
        }),
        item(l.menuResetHard, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: 'Reset to ${commit.shortSha}?',
            body:
                'Moves the current branch to this commit and discards all '
                'uncommitted changes. This cannot be undone from disk.',
            confirmLabel: 'Reset --hard',
          );
          if (ok) await actions.resetHard(sha);
        }, danger: true),
        const PopupMenuDivider(),
        item(
          l.menuEditMessage,
          () => editCommitMessage(context, ref, repoPath: path, commit: commit),
        ),
        item(
          l.menuCopySummary,
          () => Clipboard.setData(ClipboardData(text: commit.message)),
        ),
        // A commit with no body has nothing to copy under either label, and an
        // item that silently copies an empty string reads as broken.
        if (commit.body.trim().isNotEmpty) ...[
          item(
            l.menuCopyDescription,
            () => Clipboard.setData(ClipboardData(text: commit.body)),
          ),
          item(
            l.menuCopyMessage,
            () => Clipboard.setData(
              ClipboardData(
                text: joinCommitMessage(commit.message, commit.body),
              ),
            ),
          ),
        ],
        item(l.menuCopySha, () => Clipboard.setData(ClipboardData(text: sha))),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onSecondaryTapUp: (d) => _open(context, ref, d.globalPosition),
    child: child,
  );
}
