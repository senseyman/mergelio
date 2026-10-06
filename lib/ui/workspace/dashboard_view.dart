import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/dashboard.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/dashboard.dart';
import '../../state/feedback.dart';
import '../../state/workspace.dart';
import '../shell/remote_merge_confirm.dart';

/// One screen over the active group's repositories: branch, ahead/behind,
/// changes, stashes, last fetch and any operation in progress, with fetch-all
/// and a fast-forward-only bulk pull. A row click opens that repository.
class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final ws = ref.watch(workspaceProvider);
    final tabs = ws.visibleTabs;
    final batch = ref.watch(dashboardBatchProvider);
    final running = batch?.running ?? false;
    final fetchLaneBusy = ref.watch(fetchBusyProvider) != null;
    final repoLaneBusy = ref.watch(busyProvider) != null;
    final group = ws.groupById(ws.activeGroupId);
    final paths = [for (final tab in tabs) tab.path];

    Future<void> runBatch(DashboardBatchKind kind) async {
      // Read up front: the user may leave the dashboard while the batch runs,
      // and this ref goes with it.
      final ctl = ref.read(dashboardBatchProvider.notifier);
      final toasts = ref.read(toastProvider.notifier);
      final out = kind == DashboardBatchKind.fetch
          ? await ctl.fetchAll(paths, label: l.dashFetchBusy)
          : await ctl.pullAll(paths, label: l.dashPullBusy);
      if (out == null) return;
      final failed = out.count(RowRunState.failed);
      toasts.show(
        kind == DashboardBatchKind.fetch ? l.dashFetchDone : l.dashPullDone,
        description: l.dashBatchSummary(
          out.count(RowRunState.done),
          failed,
          out.count(RowRunState.skipped),
          out.count(RowRunState.cancelled),
        ),
        kind: failed > 0 ? ToastKind.warning : ToastKind.success,
      );
    }

    void refreshAll() {
      for (final p in paths) {
        ref.read(dashboardRowGenerationProvider(p).notifier).state++;
      }
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Wraps rather than overflowing: a group name is the user's own
          // text and can be any length.
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.dashTitle,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (group != null)
                _Chip(
                  text: group.name,
                  color: t.textMuted,
                  leading: _Dot(color: Color(group.colorValue)),
                ),
              Text(
                l.dashRepoCount(tabs.length),
                style: TextStyle(color: t.textFaint, fontSize: 12),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tooltip(
                message: l.dashFetchAllTooltip,
                child: OutlinedButton.icon(
                  onPressed: running || fetchLaneBusy || tabs.isEmpty
                      ? null
                      : () => runBatch(DashboardBatchKind.fetch),
                  icon: const Icon(Icons.download_outlined, size: 15),
                  label: Text(l.dashFetchAll),
                ),
              ),
              Tooltip(
                message: l.dashPullAllTooltip,
                child: OutlinedButton.icon(
                  onPressed: running || repoLaneBusy || tabs.isEmpty
                      ? null
                      : () => runBatch(DashboardBatchKind.pull),
                  icon: const Icon(Icons.fast_forward_outlined, size: 15),
                  label: Text(l.dashPullAll),
                ),
              ),
              if (batch != null && !running)
                TextButton(
                  onPressed: () =>
                      ref.read(dashboardBatchProvider.notifier).dismiss(),
                  child: Text(l.dashClearResults),
                ),
              IconButton(
                tooltip: l.dashRefresh,
                onPressed: refreshAll,
                icon: const Icon(Icons.refresh, size: 16),
              ),
            ],
          ),
        ],
      ),
    );

    return ColoredBox(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Divider(height: 1, color: t.border),
          Expanded(
            child: tabs.isEmpty
                ? Center(
                    child: Text(
                      l.dashEmpty,
                      style: TextStyle(color: t.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: tabs.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.border),
                    itemBuilder: (context, i) => _Row(
                      tab: tabs[i],
                      groupColor: ws.groupById(tabs[i].groupId)?.colorValue,
                      run: batch?.rows[tabs[i].path],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  final RepoTab tab;
  final int? groupColor;
  final RowRun? run;
  const _Row({required this.tab, required this.groupColor, this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final snap = ref.watch(repoSnapshotProvider(tab.path));

    final details = snap.when(
      loading: () => const [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ],
      error: (_, _) => [
        _Chip(
          text: l.dashUnreadable,
          color: t.danger,
          icon: Icons.error_outline,
        ),
      ],
      data: (s) => _details(l, t, s),
    );

    return InkWell(
      hoverColor: t.hover,
      onTap: () => ref.read(workspaceProvider.notifier).setActive(tab.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(color: Color(groupColor ?? t.accent.toARGB32())),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (run != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: _RunState(run: run!)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: details,
            ),
            if (run?.message case final String message) ...[
              const SizedBox(height: 4),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.danger, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _details(AppLocalizations l, AppTokens t, RepoSnapshot s) {
    final m = s.summary;
    final lastFetch = s.lastFetch;
    final age = lastFetch == null ? null : DateTime.now().difference(lastFetch);
    return [
      _Chip(
        icon: Icons.call_split,
        text: m.detached
            ? l.dashDetached
            : m.unborn
            ? '${m.branch ?? ''} · ${l.dashUnborn}'
            : m.branch ?? l.dashDetached,
        color: t.textMuted,
      ),
      if (s.op != null)
        _Chip(
          text: _opLabel(l, s.op!),
          color: t.warning,
          icon: Icons.pause_circle_outline,
        ),
      if (!m.detached && m.upstream == null)
        _Chip(text: l.dashNoUpstream, color: t.textFaint),
      if (m.upstreamGone)
        Tooltip(
          message: l.dashUpstreamGoneTooltip(m.upstream!),
          child: _Chip(
            text: l.dashUpstreamGone,
            color: t.warning,
            icon: Icons.link_off,
          ),
        ),
      if (m.upstream != null && !m.upstreamGone)
        Tooltip(
          message: l.dashAheadBehindTooltip(m.ahead, m.behind, m.upstream!),
          child: _Chip(
            text: '↑${m.ahead} ↓${m.behind}',
            color: m.behind > 0 ? t.accent : t.textMuted,
          ),
        ),
      if (m.changed == 0 && m.conflicted == 0 && m.untracked == 0)
        _Chip(text: l.dashClean, color: t.success),
      if (m.conflicted > 0)
        _Chip(text: l.dashConflicted(m.conflicted), color: t.danger),
      if (m.changed > 0)
        _Chip(text: l.dashChanged(m.changed), color: t.warning),
      if (m.untracked > 0)
        _Chip(text: l.dashUntracked(m.untracked), color: t.textMuted),
      if (s.stashCount > 0)
        _Chip(
          text: l.dashStashes(s.stashCount),
          color: t.textMuted,
          icon: Icons.inventory_2_outlined,
        ),
      _Chip(
        text: age == null
            ? l.dashNeverFetched
            : l.dashFetchedAgo(
                fetchAgeLabel(l, age.isNegative ? Duration.zero : age),
              ),
        color: t.textFaint,
        icon: Icons.schedule,
      ),
    ];
  }
}

String _opLabel(AppLocalizations l, RepoOp op) => switch (op) {
  RepoOp.merge => l.dashOpMerge,
  RepoOp.rebase => l.dashOpRebase,
  RepoOp.am => l.dashOpAm,
  RepoOp.cherryPick => l.dashOpCherryPick,
  RepoOp.revert => l.dashOpRevert,
  RepoOp.bisect => l.dashOpBisect,
};

String _skipLabel(AppLocalizations l, PullSkip s) => switch (s) {
  PullSkip.unreadable => l.dashSkipUnreadable,
  PullSkip.operation => l.dashSkipOperation,
  PullSkip.detached => l.dashSkipDetached,
  PullSkip.noUpstream => l.dashSkipNoUpstream,
  PullSkip.upstreamGone => l.dashSkipUpstreamGone,
  PullSkip.dirty => l.dashSkipDirty,
  PullSkip.diverged => l.dashSkipDiverged,
  PullSkip.upToDate => l.dashSkipUpToDate,
};

/// Where a row stands in the running or last batch.
class _RunState extends ConsumerWidget {
  final RowRun run;
  const _RunState({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final kind = ref.watch(dashboardBatchProvider.select((b) => b?.kind));
    if (run.state == RowRunState.running) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    final (text, color, icon) = switch (run.state) {
      RowRunState.queued => (l.dashRunQueued, t.textFaint, Icons.more_horiz),
      RowRunState.done => (
        kind == DashboardBatchKind.pull ? l.dashRunPulled : l.dashRunFetched,
        t.success,
        Icons.check,
      ),
      RowRunState.failed => (l.dashRunFailed, t.danger, Icons.close),
      RowRunState.cancelled => (l.dashRunCancelled, t.textFaint, Icons.block),
      RowRunState.skipped => (
        run.noRemote
            ? l.dashSkipNoRemote
            : run.pullSkip == null
            ? l.dashSkipUnreadable
            : _skipLabel(l, run.pullSkip!),
        t.textMuted,
        Icons.redo,
      ),
      RowRunState.running => ('', t.textFaint, Icons.sync),
    };
    return _Chip(text: text, color: color, icon: icon);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final Widget? leading;
  const _Chip({
    required this.text,
    required this.color,
    this.icon,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 5)],
      if (icon != null) ...[
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
      ],
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 11.5),
        ),
      ),
    ],
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
