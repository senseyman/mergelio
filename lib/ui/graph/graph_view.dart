import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/bisect.dart';
import '../../domain/git/commit_message.dart';
import '../../domain/git/models.dart';
import '../../domain/search.dart';
import '../../state/bisect.dart';
import '../../state/content_search.dart';
import '../../state/feedback.dart';
import '../../state/history_filter.dart';
import '../../state/notes.dart';
import '../../state/compare_target.dart';
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
import '../shell/branch_drop.dart';
import '../shell/repo_op_dialogs.dart';
import '../shell/resize_handle.dart';
import '../workspace/branch_switch.dart';
import '../workspace/edit_commit_message.dart';
import '../workspace/edit_note.dart';
import '../../l10n/gen/app_localizations.dart';
import 'bisect_bar.dart';
import 'commit_columns.dart';
import 'graph_derived.dart';
import 'commit_row.dart';
import 'graph_ref_filter_bar.dart';
import 'pick_bar.dart';
import 'rail_metrics.dart';
import 'squash_overlay.dart';
import 'wip_link.dart';

/// Centre panel: the commit graph for the active repo. Loads [RepoData] and
/// hands it to [GraphList]; shows nothing when no repo tab is active.
class GraphView extends ConsumerWidget {
  const GraphView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
                l.sbCouldNotRead,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            data: (d) => GraphList(
              data: d,
              // Arrives after the graph does; until then the previous answer,
              // if any, stands in rather than the connectors blinking out.
              squashLinks:
                  ref.watch(squashLinksProvider(path)).valueOrNull ?? const [],
            ),
          ),
    );
  }
}

/// The trailing row shown while history is still being paged in.
const loadMoreCommitsKey = ValueKey('graph-load-more');

/// Sits below the oldest loaded commit when the walk was cut off at the page
/// limit. Scrolling it into view is what asks for the next page, so it is on
/// screen exactly while that page is being walked. Deliberately not a spinner:
/// the row appears and disappears within a frame or two on a small repository,
/// and a running animation there would only flicker.
class _LoadingOlderRow extends StatelessWidget {
  final double height;
  const _LoadingOlderRow({required this.height});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      key: loadMoreCommitsKey,
      height: height,
      child: Center(
        child: Text(
          AppLocalizations.of(context).graphLoadingOlder,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
      ),
    );
  }
}

/// The graph itself: header with the Columns menu, then a virtualised list of
/// fixed-height rows — a WIP row on top when the working tree is dirty,
/// followed by the commits. Arrow keys move the selection and keep it visible.
class GraphList extends ConsumerStatefulWidget {
  final RepoData data;

  /// Squash-merge connectors drawn over the rail. Inferred separately from
  /// [data], so they can arrive later than the commits they join.
  final List<SquashLink> squashLinks;

  const GraphList({super.key, required this.data, this.squashLinks = const []});

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
  Set<String>? _matchHistoryFor;
  Set<String> _matchCache = const {};

  GraphDerived _deriveFor(RepoData d) {
    if (!identical(_derivedFor, d) || _derived == null) {
      _derived = computeGraphDerived(d);
      _derivedFor = d;
    }
    return _derived!;
  }

  GraphDerived? _segmentsFor;
  List<SquashLink>? _segmentLinksFor;
  List<SquashSegment> _segments = const [];

  List<SquashSegment> _segmentsOf(GraphDerived g, List<SquashLink> links) {
    if (!identical(_segmentsFor, g) || !identical(_segmentLinksFor, links)) {
      _segments = resolveSquashSegments(links, g.rowIndex, laneOf: g.laneOf);
      _segmentsFor = g;
      _segmentLinksFor = links;
    }
    return _segments;
  }

  int _matchGen = 0;

  // A selection whose commit the loaded history does not hold yet — what a
  // pull produces, naming the new HEAD before the reloaded graph arrives. Held
  // until the next reload and then dropped, so a sha that never loads (a stash
  // commit, a tip past the commit cap) cannot yank the view much later.
  String? _pendingSha;

  /// Current match set. Small histories compute inline; big ones kick a
  /// background-isolate computation and keep showing the previous set until
  /// it lands (generation counter drops stale results).
  Set<String> _matchesFor(
    RepoData d,
    CommitQuery? query,
    Set<String>? paths,
    Set<String>? content,
    Set<String>? history,
  ) {
    if (query == null || query.isEmpty) return const {};
    if (identical(_matchDataFor, d) &&
        query == _matchQueryFor &&
        identical(_matchPathsFor, paths) &&
        identical(_matchContentFor, content) &&
        identical(_matchHistoryFor, history)) {
      return _matchCache;
    }
    _matchDataFor = d;
    _matchQueryFor = query;
    _matchPathsFor = paths;
    _matchContentFor = content;
    _matchHistoryFor = history;
    // Bump the generation on every recompute so any still-in-flight isolate
    // result from a previous (data, query) is dropped when it lands.
    final gen = ++_matchGen;
    if (d.commits.length < searchIsolateThreshold) {
      _matchCache = {
        for (final c in d.commits)
          if (matchesCommit(
            c,
            query,
            pathShas: paths,
            contentShas: content,
            historyShas: history,
          ))
            c.sha,
      };
      return _matchCache;
    }
    computeMatchShas(
      d.commits,
      query,
      pathShas: paths,
      contentShas: content,
      historyShas: history,
    ).then((m) {
      if (mounted && gen == _matchGen) setState(() => _matchCache = m);
    });
    return _matchCache;
  }

  // Count of history-filter matches past the loaded page, memoized by its
  // inputs' identity: it walks every loaded commit, and the graph rebuilds on
  // every selection change.
  (RepoData, Set<String>, Set<String>?, Set<String>?)? _olderInputs;
  int _older = 0;

  int _olderFor(
    RepoData d,
    Set<String> history,
    Set<String>? paths,
    Set<String>? content,
  ) {
    final prev = _olderInputs;
    if (prev != null &&
        identical(prev.$1, d) &&
        identical(prev.$2, history) &&
        identical(prev.$3, paths) &&
        identical(prev.$4, content)) {
      return _older;
    }
    _olderInputs = (d, history, paths, content);
    return _older = olderMatchCount(
      d.commits,
      history,
      pathShas: paths,
      contentShas: content,
    );
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
  void didUpdateWidget(GraphList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pendingSha;
    if (pending == null || identical(oldWidget.data, widget.data)) return;
    // Spent whether or not the commit turned up, so this is the one retry.
    _pendingSha = null;
    final s = ref.read(settingsProvider);
    final rowHeight = RailMetrics(
      compact: s.graphCompact,
      branchWidth: s.graphBranchWidth,
      railFixedWidth: s.graphRailWidth,
    ).rowHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSha(pending, rowHeight);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasWip => widget.data.working.isNotEmpty;

  // The (repo, limit) the trailing row has already asked to grow past, so it
  // requests each page once instead of on every rebuild while it sits on
  // screen. Keyed by repo as well as limit because this state survives a tab
  // switch: two repos sitting at the same limit are two separate requests.
  (String, int)? _moreRequested;

  /// Extends the loaded history by one page. Called from the trailing row's
  /// builder, so the provider write is deferred past the frame being built.
  ///
  /// Each page doubles the limit rather than adding a fixed amount. A raised
  /// limit re-walks from scratch, so growing by a constant would walk
  /// 2k+4k+6k+… to reach the end of a long history; doubling keeps the total
  /// walked within twice what the last page alone costs.
  void _requestMoreCommits(String repo) {
    final limit = ref.read(commitLimitProvider(repo));
    if (_moreRequested == (repo, limit)) return;
    _moreRequested = (repo, limit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final limits = ref.read(commitLimitProvider(repo).notifier);
      // Something else already paged (a second graph, a repo switch); leave it.
      if (limits.state != limit) return;
      limits.state = limit * 2;
    });
  }

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

  /// A click on a commit row: Shift picks the run of rows from the anchor, Cmd
  /// (Ctrl off macOS) toggles the row in or out of the picks, and a plain
  /// click drops the picks and selects only that row.
  void _onRowTap(String sha, double rowHeight) {
    final repo = ref.read(workspaceProvider).activeTab?.path;
    if (repo != null) {
      final keys = HardwareKeyboard.instance;
      final toggle = defaultTargetPlatform == TargetPlatform.macOS
          ? keys.isMetaPressed
          : keys.isControlPressed;
      final picks = ref.read(commitPicksProvider(repo).notifier);
      final seed = ref.read(selectedCommitProvider);
      if (keys.isShiftPressed) {
        picks.state = picks.state.extend(sha, [
          for (final c in widget.data.commits) c.sha,
        ], seed: seed);
      } else if (toggle) {
        picks.state = picks.state.toggle(sha, seed: seed);
        // Toggled out: the details stay on what was already selected.
        if (!picks.state.contains(sha)) return;
      } else {
        picks.state = CommitPicks.none;
      }
    }
    _select(sha, rowHeight);
  }

  /// Brings the row for [sha] into view if it is off-screen. Uses the memoized
  /// sha→index map (O(1)) rather than scanning the commit list, so clicking a
  /// branch on a 50k-commit repo flies instantly. No-op when the sha isn't a
  /// loaded commit (e.g. a branch tip beyond the commit cap).
  void _scrollToSha(String? sha, double rowHeight, {bool arm = false}) {
    if (sha == null || !_scroll.hasClients) return;
    if (arm) _pendingSha = null;
    final wipRows = _hasWip ? 1 : 0;
    final int i;
    if (sha == wipSelection) {
      i = 0;
    } else {
      final ci = _deriveFor(widget.data).rowIndex[sha];
      if (ci == null) {
        // Only a fresh request waits for its commit; a retry that misses is
        // the end of it.
        if (arm) _pendingSha = sha;
        return;
      }
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event, double rowHeight) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // N / ⇧N step through search matches while a search is active and the
    // graph (not the search field) has focus.
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      final query = ref.read(searchQueryProvider);
      if (query != null && !query.isEmpty) {
        // Reuses whatever the last build computed, path, content and history
        // shas included.
        final matches = _matchesFor(
          widget.data,
          query,
          _matchPathsFor,
          _matchContentFor,
          _matchHistoryFor,
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
    final l = AppLocalizations.of(context);
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
        (_) => _scrollToSha(sha, metrics.rowHeight, arm: true),
      );
    });

    // Kept listed while the graph is up, so a row's menu can say at once
    // whether its commit has a note. Listened to, not watched: a new list
    // does not redraw the graph.
    final notesRepo = ref.watch(
      workspaceProvider.select((w) => w.activeTab?.path),
    );
    if (notesRepo != null) ref.listen(noteIndexProvider(notesRepo), (_, _) {});

    final derived = _deriveFor(d);
    final maxLane = derived.maxLane;
    final labels = derived.labels;
    final segments = _segmentsOf(derived, widget.squashLinks);
    final stashBySha = {for (final s in d.stashes) s.sha: s.ref};
    final wipLink = _hasWip ? wipLinkEnds(metrics, derived.head) : null;

    final wipRows = _hasWip ? 1 : 0;
    final moreRows = d.hasMoreCommits ? 1 : 0;

    final query = ref.watch(searchQueryProvider);
    // The commits that touched the followed file, if one is being followed.
    // Only the loaded value counts: while the read is in flight the filter has
    // no shas yet and the graph shows no matches.
    final repo = ref.watch(workspaceProvider.select((w) => w.activeTab?.path));
    final picks = repo == null
        ? CommitPicks.none
        : ref.watch(commitPicksProvider(repo));
    // Read once for the whole list rather than per row, so no two rows can
    // draw their pills from different snapshots. The context menu reads the
    // provider again when it opens, by which time a verdict may have landed;
    // that is the point — the menu offers what is true now, not what the
    // list was painted with.
    //
    // A read that failed leaves the pills off: a verdict shown against a
    // commit nobody could confirm is worse than no verdict shown at all.
    final bisectState = repo == null
        ? null
        : ref.watch(bisectStateProvider(repo)).bisect;
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
    // The commits git reported for the author and date range, on the same
    // terms again. Read from the whole history, so it also knows how many
    // matches sit past the loaded page.
    final history = (query == null || !query.hasHistoryFilter || repo == null)
        ? null
        : ref.watch(
            historyFilterProvider(
              HistoryFilterKey(
                repo,
                query.author.trim(),
                since: query.since,
                until: query.until,
                noMerges: query.hideMerges,
                stamp: historyStamp(d),
              ),
            ),
          );
    final historyShas = history?.valueOrNull;
    final matchShas = _matchesFor(
      d,
      query,
      pathShas,
      content?.valueOrNull,
      historyShas,
    );
    // Only counted once every git-backed filter that is on has answered, so a
    // filter still loading cannot inflate the number.
    final older =
        (query == null ||
            historyShas == null ||
            !d.hasMoreCommits ||
            (query.path.isNotEmpty && pathShas == null) ||
            (query.content.isNotEmpty && content?.valueOrNull == null))
        ? 0
        : _olderFor(
            d,
            historyShas,
            query.path.isEmpty ? null : pathShas,
            query.content.isEmpty ? null : content?.valueOrNull,
          );

    final graph = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mounted above the search/header row rather than inside either
        // branch of it, so a bisect in progress stays visible even while the
        // user is searching — the bar renders nothing itself when no bisect
        // is running.
        if (repo != null)
          BisectBar(
            repoPath: repo,
            onJumpToCommit: (sha) {
              _focus.requestFocus();
              _select(sha, metrics.rowHeight);
            },
          ),
        if (repo != null) PickBar(repoPath: repo, commits: d.commits),
        if (repo != null) GraphRefFilterBar(repoPath: repo, data: d),
        if (query != null)
          _SearchBar(
            query: query,
            matchCount: matchShas.length,
            olderCount: older,
            searching:
                (content?.isLoading ?? false) || (history?.isLoading ?? false),
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
            // Same paging as scrolling to the end, so a double click, or a
            // click while the trailing row is already loading, asks once.
            onLoadOlder: () {
              if (repo != null) _requestMoreCommits(repo);
            },
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
                    itemCount: d.commits.length + wipRows + moreRows,
                    itemBuilder: (context, i) {
                      // Trailing row on truncated history: reaching it means
                      // the user scrolled to the end of what is loaded, so ask
                      // for the next page. The row is returned whether or not
                      // a repo is active — the data outlives a closing tab by
                      // a frame, and falling through would index past the end
                      // of the commit list.
                      if (moreRows == 1 && i == d.commits.length + wipRows) {
                        if (repo != null) _requestMoreCommits(repo);
                        return _LoadingOlderRow(height: metrics.rowHeight);
                      }
                      if (_hasWip && i == 0) {
                        return _WipRow(
                          metrics: metrics,
                          head: derived.head,
                          maxLane: maxLane,
                          branchColumn: cols['branch'] ?? true,
                          fileCount: d.working.length,
                          selected: selected == wipSelection,
                          onTap: () {
                            _focus.requestFocus();
                            if (repo != null) {
                              ref
                                      .read(commitPicksProvider(repo).notifier)
                                      .state =
                                  CommitPicks.none;
                            }
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
                      final showBranchLabel =
                          rowLabels.isNotEmpty &&
                          !listEquals(rowLabels, prevLabels);
                      // Labels and the rest of the row both ask the one rule in
                      // [resolveBranchDrop]; only the spot they report differs.
                      BranchDropTarget? dropTarget(
                        String source,
                        DropSpot spot,
                      ) => resolveBranchDrop(
                        source: source,
                        spot: spot,
                        branches: d.branches,
                        remoteBranches: d.remoteBranches,
                      );
                      void openDrop(String source, DropSpot spot, Offset at) {
                        final target = dropTarget(source, spot);
                        final repoPath = ref
                            .read(workspaceProvider)
                            .activeTab
                            ?.path;
                        if (target == null || repoPath == null) return;
                        showBranchDropMenu(
                          this.context,
                          ref,
                          repoPath: repoPath,
                          source: source,
                          target: target,
                          at: at,
                        );
                      }

                      final commitSpot = DropSpot.commit(
                        c.sha,
                        isStash: stashBySha.containsKey(c.sha),
                      );
                      final row = _CommitContextMenu(
                        commit: c,
                        // Only the segment top names its branches, so only
                        // there can the menu offer to copy them.
                        branchLabels: showBranchLabel
                            ? rowLabels
                            : const <String>[],
                        child: CommitRow(
                          commit: c,
                          branchLabels: rowLabels,
                          showBranchLabel: showBranchLabel,
                          metrics: metrics,
                          maxLane: maxLane,
                          cols: cols,
                          dateFormat: dateFormat,
                          stashLabel: stashBySha[c.sha],
                          // While commits are picked the highlight shows the
                          // picks alone, so toggling the selected row out
                          // visibly drops it.
                          selected: picks.isEmpty
                              ? selected == c.sha
                              : picks.contains(c.sha),
                          searchMatch: query == null || query.isEmpty
                              ? null
                              : matchShas.contains(c.sha),
                          bisectKind: bisectState?.kindOf(c.sha),
                          onTap: () {
                            _focus.requestFocus();
                            _onRowTap(c.sha, metrics.rowHeight);
                          },
                          acceptsBranchDrop: (source, chip) =>
                              dropTarget(source, DropSpot.label(chip)) != null,
                          onBranchDropped: (source, chip, at) =>
                              openDrop(source, DropSpot.label(chip), at),
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
                      return DragTarget<String>(
                        onWillAcceptWithDetails: (dd) =>
                            dropTarget(dd.data, commitSpot) != null,
                        onAcceptWithDetails: (dd) =>
                            openDrop(dd.data, commitSpot, dd.offset),
                        builder: (ctx, candidates, _) => Container(
                          color: candidates.isNotEmpty
                              ? context.tokens.accent.withValues(alpha: 0.14)
                              : null,
                          child: row,
                        ),
                      );
                    },
                  ),
                  // The uncommitted-changes row hangs from HEAD, which can sit
                  // well below it on another lane; this joins the two.
                  if (wipLink != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: WipLinkPainter(
                              link: wipLink,
                              railWidth: metrics.railWidth(maxLane),
                              color: context.tokens.warning,
                              scroll: _scroll,
                              dx: (cols['branch'] ?? true)
                                  ? metrics.branchWidth
                                  : 0,
                            ),
                          ),
                        ),
                      ),
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
    return Semantics(container: true, label: l.a11yCommitGraph, child: graph);
  }
}

/// How long the content and author fields wait for typing to stop before
/// asking git. Each run walks the whole history — the content one reads every
/// diff — so a git process per keystroke would leave the machine doing
/// nothing else.
const _contentDebounce = Duration(milliseconds: 350);

/// Global-search bar shown in place of the header while a search is open.
class _SearchBar extends StatefulWidget {
  final CommitQuery query;
  final int matchCount;

  /// Commits git reported for the author/date filter that the graph has not
  /// loaded yet. Shown as a button that pages in more history.
  final int olderCount;

  /// True while the pickaxe is still running, so an empty result reads as
  /// "not finished yet" rather than "nothing found".
  final bool searching;
  // 1-based position of the selected match, 0 when the selection is not a
  // match. Rendered as "current / total".
  final int currentIndex;
  final ValueChanged<CommitQuery> onChanged;
  final VoidCallback onClose;
  final void Function(bool forward) onJump;
  final VoidCallback onLoadOlder;
  const _SearchBar({
    required this.query,
    required this.matchCount,
    required this.olderCount,
    required this.searching,
    required this.currentIndex,
    required this.onChanged,
    required this.onClose,
    required this.onJump,
    required this.onLoadOlder,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _authorDebounce?.cancel();
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

  // The author field has its own timer: typing in it must not cancel a
  // content search that is still waiting to run, and the other way round.
  Timer? _authorDebounce;

  void _typedAuthor(String v) {
    _authorDebounce?.cancel();
    _authorDebounce = Timer(_contentDebounce, () => _setAuthor(v));
  }

  /// Applies the author at once — what Enter does, skipping the wait.
  void _setAuthor(String v) {
    _authorDebounce?.cancel();
    if (widget.query.author == v) return;
    widget.onChanged(widget.query.copyWith(author: v));
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
                  hintText: l.gvSearchCommits,
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
            // Author filter feeds CommitQuery.author, answered by git over the
            // whole history, name or email.
            SizedBox(
              width: 120,
              child: Tooltip(
                message: l.searchAuthorHelp,
                child: TextField(
                  key: const ValueKey('search:author'),
                  onChanged: _typedAuthor,
                  onSubmitted: _setAuthor,
                  style: TextStyle(color: t.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l.gvAuthorFilter,
                    hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Flexible so a long range label shortens rather than pushing the
            // match counter and buttons off the bar.
            Flexible(
              child: _DateChip(
                since: query.since,
                until: query.until,
                // Reads the query when the range is picked, not when the bar
                // was built: the custom picker stays open long enough for the
                // query to move on underneath it.
                onChanged: (since, until) {
                  if (!mounted) return;
                  widget.onChanged(widget.query.withDates(since, until));
                },
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
            if (widget.olderCount > 0 && !widget.searching)
              Tooltip(
                message: l.searchOlderMatchesHelp(widget.olderCount),
                child: InkWell(
                  key: const ValueKey('search:older'),
                  onTap: widget.onLoadOlder,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      '+${widget.olderCount}',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            IconButton(
              iconSize: 16,
              tooltip: l.gvPrevMatch,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => onJump(false),
            ),
            IconButton(
              iconSize: 16,
              tooltip: l.gvNextMatch,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => onJump(true),
            ),
            IconButton(
              iconSize: 16,
              tooltip: l.gvCloseSearch,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// The choices the date chip's menu offers. The relative ones end today and
/// count today as one of their days.
enum _DateChoice { any, week, month, year, custom }

/// Date-range filter of the search bar: shows the active range and opens a
/// menu of common ranges, plus a picker for any other.
class _DateChip extends StatelessWidget {
  final DateTime? since;
  final DateTime? until;
  final void Function(DateTime? since, DateTime? until) onChanged;
  const _DateChip({
    required this.since,
    required this.until,
    required this.onChanged,
  });

  Future<void> _choose(BuildContext context, _DateChoice choice) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // The range is inclusive, so "last 7 days" starts six days back.
    DateTime days(int n) =>
        DateTime(today.year, today.month, today.day - (n - 1));
    switch (choice) {
      case _DateChoice.any:
        onChanged(null, null);
      case _DateChoice.week:
        onChanged(days(7), null);
      case _DateChoice.month:
        onChanged(days(30), null);
      case _DateChoice.year:
        onChanged(DateTime(today.year - 1, today.month, today.day + 1), null);
      case _DateChoice.custom:
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(1970),
          lastDate: today,
          initialDateRange: since == null
              ? null
              : DateTimeRange(
                  start: since!.isAfter(today) ? today : since!,
                  end: until == null || until!.isAfter(today) ? today : until!,
                ),
        );
        if (range != null) onChanged(range.start, range.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final ml = MaterialLocalizations.of(context);
    final on = since != null || until != null;
    final label = switch ((since, until)) {
      (null, null) => l.filterDate,
      (final DateTime s, null) => l.filterDateSince(ml.formatShortDate(s)),
      (null, final DateTime u) => l.filterDateUntil(ml.formatShortDate(u)),
      (final DateTime s, final DateTime u) =>
        '${ml.formatShortDate(s)} – ${ml.formatShortDate(u)}',
    };
    return PopupMenuButton<_DateChoice>(
      key: const ValueKey('search:date'),
      tooltip: l.filterDateHelp,
      onSelected: (c) => _choose(context, c),
      itemBuilder: (_) => [
        PopupMenuItem(value: _DateChoice.any, child: Text(l.filterDateAny)),
        PopupMenuItem(value: _DateChoice.week, child: Text(l.filterDateWeek)),
        PopupMenuItem(value: _DateChoice.month, child: Text(l.filterDateMonth)),
        PopupMenuItem(value: _DateChoice.year, child: Text(l.filterDateYear)),
        PopupMenuItem(
          value: _DateChoice.custom,
          child: Text(l.filterDateCustom),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? t.accent.withValues(alpha: 0.16) : null,
          border: Border.all(color: on ? Colors.transparent : t.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: on ? t.accent : t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
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
    final names = graphColumnLabels(l);
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
            tooltip: l.gvColumns,
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
                    l.gvColumns,
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

  /// HEAD's commit, which the ring sits above; null when it is not loaded.
  final WipHead? head;
  const _WipRow({
    required this.head,
    required this.metrics,
    required this.maxLane,
    required this.branchColumn,
    required this.fileCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  painter: WipRailPainter(
                    m: metrics,
                    color: t.warning,
                    lane: wipRingLane(head),
                    strand: wipRingStrand(head),
                  ),
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
                      l.gvUncommittedFiles(fileCount),
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

/// Right-click scaffold; every mutation lands in a later stage, Copy SHA works
/// now.
/// Per-commit right-click menu wired to real, undoable git operations.
class _CommitContextMenu extends ConsumerWidget {
  final Commit commit;

  /// Branches named in this row's left gutter, as shown — a remote-only branch
  /// keeps its `remote/` prefix — so the copied name is the one git accepts as
  /// a ref. Empty when the row names none.
  final List<String> branchLabels;
  final Widget child;
  const _CommitContextMenu({
    required this.commit,
    required this.branchLabels,
    required this.child,
  });

  /// Cherry-picks or reverts this commit. A merge has no single set of changes
  /// to replay, so git needs the mainline parent first — asking beats the bare
  /// "commit is a merge but no -m option was given" git would otherwise
  /// return.
  Future<void> _replay(
    BuildContext context,
    WidgetRef ref,
    String path,
    MainlineOp op,
  ) => replayCommit(
    commit: commit,
    op: op,
    actions: ref.read(repoActionsProvider(path)),
    pick: () {
      final commits =
          ref.read(repoDataProvider(path)).valueOrNull?.commits ??
          const <Commit>[];
      return showMainlineDialog(
        context,
        commit: commit,
        op: op,
        subjects: parentSubjects(commit, commits),
      );
    },
  );

  Future<void> _open(BuildContext context, WidgetRef ref, Offset at) async {
    final path = ref.read(workspaceProvider).activeTab?.path;
    if (path == null) return;
    final actions = ref.read(repoActionsProvider(path));
    final sha = commit.sha;
    final mark = ref.read(compareMarkProvider);
    final marked = mark != null && mark.repoPath == path && mark.sha == sha;
    final bisect = ref.read(bisectStateProvider(path));
    final l = AppLocalizations.of(context);
    // A right-click on one of several picked rows acts on all of them.
    final commits =
        ref.read(repoDataProvider(path)).valueOrNull?.commits ??
        const <Commit>[];
    final picks = ref.read(commitPicksProvider(path));
    final picked = picks.contains(sha)
        ? picks.oldestFirst([for (final c in commits) c.sha]).length
        : 0;
    // Labelled from what is already listed: a right-click does not wait on
    // git. Before the list is in, or when it failed, the item offers Add, and
    // the dialog still opens on the note git has.
    final hasNote =
        ref.read(noteIndexProvider(path)).valueOrNull?.containsKey(sha) ??
        false;

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
        if (picked > 1) ...[
          item(
            l.pickMenuCherryPick(picked),
            () => cherryPickPicks(ref, l, path, commits),
          ),
          item(
            l.pickMenuNoCommit(picked),
            () => cherryPickPicks(ref, l, path, commits, noCommit: true),
          ),
          const PopupMenuDivider(),
        ],
        item(l.menuCheckout, () => actions.checkout(sha)),
        item(l.menuCreateBranch, () async {
          final name = await showInputDialog(
            context,
            title: l.ropCreateBranchTitle,
            label: l.ropBranchName,
          );
          if (name != null) await actions.createBranch(name, at: sha);
        }),
        item(l.menuCreateTag, () => showTagDialog(context, ref, path, at: sha)),
        item(
          l.menuCherryPick,
          () => _replay(context, ref, path, MainlineOp.cherryPick),
        ),
        item(
          l.menuRevert,
          () => _replay(context, ref, path, MainlineOp.revert),
        ),
        item(l.menuRebaseHere, () async {
          final steps = await actions.rebaseStepsFrom(sha);
          if (steps.isEmpty) return;
          if (await actions.rebaseCrossesMerge(sha)) {
            ref
                .read(toastProvider.notifier)
                .show(
                  l.gvCannotRebaseTitle,
                  description: l.gvCannotRebaseBody(commit.shortSha),
                  kind: ToastKind.warning,
                );
            return;
          }
          final stacked = await actions.rebaseStackedBranches(sha);
          if (!context.mounted) return;
          final plan = await showRebaseEditor(
            context,
            steps: steps,
            onto: commit.shortSha,
            stackedBranches: [for (final b in stacked.values) ...b],
          );
          if (plan == null) return;
          // Unchanged picks onto an ancestor replay to the same shas, so a
          // stacked branch has nowhere to move either.
          if (await actions.isRebaseRedundant(sha, steps, plan.steps)) {
            ref
                .read(toastProvider.notifier)
                .show(
                  l.gvNothingToRebaseTitle,
                  description: l.gvNothingToRebaseBody(commit.shortSha),
                );
            return;
          }
          await actions.rebase(sha, plan.steps, updateRefs: plan.updateRefs);
        }),
        item(l.menuCreateFixup, () => actions.prepareFixup(commit.message)),
        item(l.menuResetMixed, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: l.gvResetMixedTitle(commit.shortSha),
            body: l.gvResetMixedBody,
            confirmLabel: l.gvResetMixed,
          );
          if (ok) await actions.resetMixed(sha);
        }),
        item(l.menuResetHard, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: l.gvResetTitle(commit.shortSha),
            body: l.gvResetBody,
            confirmLabel: l.gvResetHard,
          );
          if (ok) await actions.resetHard(sha);
        }, danger: true),
        const PopupMenuDivider(),
        // The marked commit is the one place the mark can be taken back: it
        // has no second side to compare against, and re-marking it would be a
        // no-op that leaves the user stuck with a mark they changed their mind
        // about.
        if (marked)
          item(l.menuClearCompareMark, () {
            ref.read(compareMarkProvider.notifier).state = null;
          })
        else
          item(l.menuMarkCompare, () {
            ref.read(compareMarkProvider.notifier).state = CompareMark(
              repoPath: path,
              sha: sha,
            );
          }),
        // The mark is the left side; this commit is the right one. A mark from
        // another repository resolves against the wrong history, so it is not
        // offered here either.
        if (mark != null && mark.repoPath == path && !marked)
          item(l.menuCompareWith(compareRefLabel(mark.sha)), () {
            ref.read(compareTargetProvider.notifier).state = CompareTarget(
              repoPath: path,
              from: mark.sha,
              to: sha,
            );
            ref.read(compareMarkProvider.notifier).state = null;
          }),
        const PopupMenuDivider(),
        item(
          l.menuEditMessage,
          () => editCommitMessage(context, ref, repoPath: path, commit: commit),
        ),
        item(
          hasNote ? l.menuEditNote : l.menuAddNote,
          () => editCommitNote(context, ref, repoPath: path, sha: sha),
        ),
        if (hasNote)
          item(l.menuRemoveNote, () => actions.removeNote(sha), danger: true),
        // One menu covers the whole row, gutter included, so a right-click
        // anywhere on it reaches both the commit's actions and the names of
        // the branches sitting on it — each named, since a row can carry
        // several. They lead the copy group: reaching a branch name was one
        // click on its chip before, and it stays near the top here.
        for (final label in branchLabels)
          item(
            l.sbCopyNamed(label),
            () => Clipboard.setData(ClipboardData(text: label)),
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
        // Nothing bisect-related is offered while the state is unknown, so
        // the divider that heads the group goes with it. `git bisect start`
        // on a hunt already running throws its refs away and exits 0, which
        // is one click between a failed read and a search that is gone.
        if (!bisect.unknown) ...[
          const PopupMenuDivider(),
          // Starting only makes sense with no bisect already in progress, and
          // recording a verdict only makes sense with one running — the two
          // groups are mutually exclusive, never shown together.
          if (bisect.bisect == null)
            item(l.bisectMenuStart, () => actions.startBisect(sha))
          else ...[
            item(
              l.bisectMenuGood,
              () => actions.markBisect(sha, BisectKind.good),
            ),
            item(
              l.bisectMenuBad,
              () => actions.markBisect(sha, BisectKind.bad),
            ),
            item(
              l.bisectMenuSkip,
              () => actions.markBisect(sha, BisectKind.skip),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onSecondaryTapUp: (d) => _open(context, ref, d.globalPosition),
    child: child,
  );
}
