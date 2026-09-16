import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/reflog.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_selection.dart';
import '../../state/reflog.dart';
import '../../state/repo_actions.dart';
import '../../state/settings_controller.dart';
import '../../state/undo_stack.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'sidebar_section.dart';

/// Sidebar section listing HEAD's reflog: where HEAD has been, and what moved
/// it. This is the recovery path for commits no ref points at any more, so the
/// list itself is read-only and every row action addresses its entry by sha.
class ReflogSection extends ConsumerWidget {
  final String repoPath;
  const ReflogSection({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final collapsed = ref.watch(
      settingsProvider.select((s) => s.collapsedSections),
    );
    final ctl = ref.read(settingsProvider.notifier);
    // Collapsed until asked for, unlike the other sections, which default to
    // open: this one spends a subprocess to fill and is a tool people reach
    // for when something went wrong, not a list to keep an eye on.
    final open = !(collapsed['reflog'] ?? true);
    // Anything that moves a ref writes a reflog entry, so an open section has
    // to re-read once an operation lands. The undo stack is the signal for
    // that: it gains an entry exactly once per completed operation, and once
    // more per undo or redo, which move refs too. Repository data is the wrong
    // signal — it resolves asynchronously, so listening to it re-reads once
    // when it first loads and again on each loading/data transition.
    //
    // Listening from here rather than from the action layer is what keeps a
    // collapsed section free: invalidating a provider makes it fetch whether
    // anything listens or not.
    if (open) {
      ref.listen(undoProvider(repoPath), (_, _) {
        ref.invalidate(reflogProvider(repoPath));
      });
    }
    final async = open ? ref.watch(reflogProvider(repoPath)) : null;
    final entries = async?.valueOrNull ?? const <ReflogEntry>[];
    // A failed read must not fall through to the empty state. Telling someone
    // hunting for lost commits that there are no entries, when git merely
    // failed, is the one wrong answer this section can give.
    final failed = async?.hasError ?? false;
    final query = ref.watch(reflogFilterProvider(repoPath)).trim();
    final visible = query.isEmpty
        ? entries
        : entries.where((e) => _matches(e, query.toLowerCase())).toList();

    return SidebarSection(
      id: 'reflog',
      icon: Icons.history,
      label: l.sbReflog,
      // No count while collapsed: nothing has been read, and a `0` there would
      // claim an empty reflog rather than an unopened one.
      count: open && !failed ? visible.length : null,
      emptyLabel: l.sbNoReflog,
      open: open,
      onToggle: () => ctl.toggleSection('reflog'),
      children: [
        if (failed)
          _NoticeRow(label: l.sbReflogFailed, danger: true)
        else ...[
          if (entries.length >= reflogFilterThreshold)
            _FilterField(repoPath: repoPath),
          // Distinct from the section's empty state: "no entries" would claim
          // the reflog is bare when it is only the query that matches nothing.
          if (visible.isEmpty && query.isNotEmpty)
            _NoticeRow(label: l.sbReflogNoMatches)
          else
            for (final e in visible) _ReflogRow(entry: e, repoPath: repoPath),
          // A reflog exactly one page long says this too. Over-warning costs
          // a line of text; under-warning hides the entry someone needs. The
          // unfiltered count decides it: the cap applied to the read.
          if (entries.length >= reflogPageSize)
            _NoticeRow(label: l.sbReflogTruncated(reflogPageSize)),
        ],
      ],
    );
  }
}

/// Matches a filter against everything on the row that a person might recall:
/// the verb, the message, the position, and the sha they half-remember.
bool _matches(ReflogEntry e, String lower) =>
    e.action.toLowerCase().contains(lower) ||
    e.detail.toLowerCase().contains(lower) ||
    e.selector.toLowerCase().contains(lower) ||
    e.sha.toLowerCase().contains(lower);

/// The filter box shown above a long reflog. Stateful for its controller, so
/// the controller is disposed with the field rather than on a rebuild.
class _FilterField extends ConsumerStatefulWidget {
  final String repoPath;
  const _FilterField({required this.repoPath});

  @override
  ConsumerState<_FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends ConsumerState<_FilterField> {
  late final _controller = TextEditingController(
    text: ref.read(reflogFilterProvider(widget.repoPath)),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 12, 6),
      child: TextField(
        controller: _controller,
        style: TextStyle(color: t.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: l.sbReflogFilter,
          hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
          prefixIcon: Icon(Icons.search, size: 14, color: t.textFaint),
          prefixIconConstraints: const BoxConstraints(minWidth: 22),
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
        onChanged: (v) =>
            ref.read(reflogFilterProvider(widget.repoPath).notifier).state = v,
      ),
    );
  }
}

/// One reflog entry: its selector and the verb git recorded on one line, the
/// rest of the message under it, and the sha it pointed at on the right.
class _ReflogRow extends ConsumerWidget {
  final ReflogEntry entry;
  final String repoPath;
  const _ReflogRow({required this.entry, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final dateFormat = ref.watch(settingsProvider.select((s) => s.dateFormat));
    final clock = ref.watch(settingsProvider.select((s) => s.clockFormat));
    final selected = ref.watch(selectedCommitProvider) == entry.sha;
    return InkWell(
      hoverColor: t.hover,
      // The graph scrolls to whatever the selection holds, so a plain click is
      // the non-destructive way to go look at a recovered commit.
      onTap: () => ref.read(selectedCommitProvider.notifier).state = entry.sha,
      onSecondaryTapUp: (d) => _menu(context, ref, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 5, 10, 5),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                // The row ellipsizes, and the full sha and timestamp are what
                // tell two similar entries apart when recovering.
                message: [
                  if (entry.detail.isEmpty)
                    entry.action
                  else
                    '${entry.action}: ${entry.detail}',
                  entry.sha,
                  formatCommitDate(
                    entry.date,
                    format: dateFormat,
                    withTime: true,
                    clock: clock,
                    offset: entry.dateOffset,
                  ),
                ].join('\n'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.selector,
                          style: TextStyle(
                            color: selected ? t.accent : t.textPrimary,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            entry.action,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (entry.detail.isNotEmpty)
                      Text(
                        entry.detail,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    // When it happened is half of recognising an entry — "the
                    // one from yesterday" is how people describe what they
                    // lost. Its own line: the sidebar has height to spare and
                    // no width.
                    Text(
                      formatCommitDate(
                        entry.date,
                        format: dateFormat,
                        offset: entry.dateOffset,
                      ),
                      style: TextStyle(color: t.textFaint, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              entry.shortSha,
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l = AppLocalizations.of(context);
    final actions = ref.read(repoActionsProvider(repoPath));
    final sha = entry.sha;

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
        // Checkout lands on a detached HEAD, which is the safe way to look at
        // a recovered commit — but it is also a state people arrive in by
        // accident and struggle to leave, and someone reaching for the reflog
        // is already having a bad day. Worth one sentence of warning.
        item(l.menuCheckout, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: l.sbReflogDetachTitle(entry.shortSha),
            body: l.sbReflogDetachBody,
            confirmLabel: l.sbReflogDetach,
          );
          if (ok) await actions.checkout(sha);
        }),
        // The recovery that moves nothing: name the entry and it stops being
        // reachable only through the reflog.
        item(l.menuCreateBranch, () async {
          final name = await showInputDialog(
            context,
            title: l.ropCreateBranchTitle,
            label: l.ropBranchName,
          );
          if (name != null) await actions.createBranch(name, at: sha);
        }),
        item(l.sbCopySha, () => Clipboard.setData(ClipboardData(text: sha))),
        item(l.menuResetMixed, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: l.gvResetMixedTitle(entry.shortSha),
            body: l.gvResetMixedBody,
            confirmLabel: l.gvResetMixed,
          );
          if (ok) await actions.resetMixed(sha);
        }),
        item(l.menuResetHard, () async {
          final ok = await confirmDestructive(
            ref,
            context,
            title: l.gvResetTitle(entry.shortSha),
            body: l.gvResetBody,
            confirmLabel: l.gvResetHard,
          );
          if (ok) await actions.resetHard(sha);
        }, danger: true),
      ],
    );
  }
}

/// A line among the rows that is not itself an entry: a read failure, or a
/// note that the list was cut short.
class _NoticeRow extends StatelessWidget {
  final String label;
  final bool danger;
  const _NoticeRow({required this.label, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 4, 12, 4),
      child: Text(
        label,
        style: TextStyle(color: danger ? t.danger : t.textFaint, fontSize: 11),
      ),
    );
  }
}
