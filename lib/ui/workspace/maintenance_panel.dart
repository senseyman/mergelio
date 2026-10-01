import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_service.dart';
import '../../domain/git/maintenance.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_selection.dart';
import '../../state/maintenance.dart';
import '../../state/repo_actions.dart';
import '../../state/settings_controller.dart';
import '../../state/worktrees.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'worktree_dialogs.dart';

/// Opens the maintenance panel for [repoPath].
Future<void> showMaintenancePanel(BuildContext context, String repoPath) =>
    showAppModal<void>(
      context: context,
      title: AppLocalizations.of(context).mntTitle,
      icon: Icons.cleaning_services_outlined,
      width: 760,
      body: MaintenancePanel(repoPath: repoPath),
    );

/// Where a repository's disk space goes, and the clean-ups that give some of
/// it back. Opening it only reads; every clean-up asks first.
class MaintenancePanel extends ConsumerStatefulWidget {
  final String repoPath;
  const MaintenancePanel({super.key, required this.repoPath});

  @override
  ConsumerState<MaintenancePanel> createState() => _MaintenancePanelState();
}

class _MaintenancePanelState extends ConsumerState<MaintenancePanel> {
  @override
  void initState() {
    super.initState();
    // A shown scan goes out of date when any ref moves: on open, since it may
    // have been taken earlier in the session, and again each time the refs
    // move while the panel is up.
    ref.listenManual(
      maintenanceRefsKeyProvider(widget.repoPath),
      (_, _) => ref.read(blobScanProvider(widget.repoPath).notifier).recheck(),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final path = widget.repoPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Section(
          title: l.mntStorage,
          child: _Storage(repoPath: path),
        ),
        _Section(
          title: l.mntBlobs,
          child: _Blobs(repoPath: path),
        ),
        _Section(
          title: l.mntBranches,
          child: _Branches(repoPath: path),
        ),
        _Section(
          title: l.mntWorktrees,
          child: _Worktrees(repoPath: path),
        ),
        _Section(
          title: l.mntReflog,
          child: _Reflog(repoPath: path),
        ),
        _Section(
          title: l.mntHousekeeping,
          last: true,
          child: _Housekeeping(repoPath: path),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final bool last;
  const _Section({required this.title, required this.child, this.last = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

TextStyle _body(AppTokens t, {Color? color}) =>
    TextStyle(color: color ?? t.textPrimary, fontSize: 13);

TextStyle _faint(AppTokens t) => TextStyle(color: t.textFaint, fontSize: 12);

Widget _loading() => const Padding(
  padding: EdgeInsets.symmetric(vertical: 4),
  child: LinearProgressIndicator(minHeight: 2),
);

/// What git said, when it said anything; otherwise the short reason. Never
/// the exception's own rendering, which is a developer's dump.
String _reason(Object error) {
  if (error is GitException) {
    final err = error.result?.err ?? '';
    return err.isNotEmpty ? err : error.message;
  }
  return '$error';
}

Widget _failed(BuildContext context, Object error) => Text(
  AppLocalizations.of(context).mntReadFailed(_reason(error)),
  style: _body(context.tokens, color: context.tokens.danger),
);

class _Storage extends ConsumerWidget {
  final String repoPath;
  const _Storage({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(maintenanceSizeProvider(repoPath))
        .when(
          loading: _loading,
          error: (e, _) => _failed(context, e),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.mntStorageTotal(formatBytes(s.disk.totalBytes)),
                style: _body(t).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _SizeRow(
                label: l.mntPacks,
                bytes: s.disk.packBytes,
                detail: l.mntPackCount(s.counts.packCount),
              ),
              _SizeRow(
                label: l.mntLoose,
                bytes: s.disk.looseBytes,
                detail: l.mntLooseCount(s.counts.looseCount),
              ),
              _SizeRow(label: l.mntLfs, bytes: s.disk.lfsBytes),
              _SizeRow(label: l.mntOther, bytes: s.disk.otherBytes),
              const SizedBox(height: 4),
              Text(l.mntStorageNote, style: _faint(t)),
            ],
          ),
        );
  }
}

class _SizeRow extends StatelessWidget {
  final String label;
  final int bytes;
  final String? detail;
  const _SizeRow({required this.label, required this.bytes, this.detail});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: _body(t),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (detail != null) ...[
            Flexible(
              child: Text(
                detail!,
                style: _faint(t),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 76,
            child: Text(
              formatBytes(bytes),
              textAlign: TextAlign.right,
              style: AppFonts.mns(size: 12, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blobs extends ConsumerWidget {
  final String repoPath;
  const _Blobs({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final s = ref.watch(blobScanProvider(repoPath));
    final ctl = ref.read(blobScanProvider(repoPath).notifier);
    final settings = ref.watch(settingsProvider);
    final result = s.result;
    final scannedAt = result == null
        ? null
        : DateTime.tryParse(result.scannedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            if (s.scanning)
              Text(l.mntScanning, style: _body(t))
            else if (scannedAt != null)
              Text(
                l.mntScannedAt(
                  formatCommitDate(
                    scannedAt,
                    format: settings.dateFormat,
                    withTime: true,
                    clock: settings.clockFormat,
                  ),
                ),
                style: _body(t),
              )
            else
              Text(l.mntBlobsIntro, style: _body(t)),
            if (s.scanning)
              TextButton(onPressed: ctl.cancel, child: Text(l.cancel))
            else
              OutlinedButton(
                onPressed: ctl.scan,
                child: Text(result == null ? l.mntScan : l.mntRescan),
              ),
          ],
        ),
        if (s.scanning) _loading(),
        if (s.stale && !s.scanning) ...[
          const SizedBox(height: 4),
          Text(l.mntScanStale, style: _body(t, color: t.warning)),
        ],
        if (s.error != null) ...[
          const SizedBox(height: 4),
          Text(l.mntScanFailed(s.error!), style: _body(t, color: t.danger)),
        ],
        if (result != null) ...[
          const SizedBox(height: 8),
          if (result.blobs.isEmpty) Text(l.mntNoBlobs, style: _faint(t)),
          for (final b in result.blobs) _BlobRow(blob: b),
        ],
      ],
    );
  }
}

class _BlobRow extends ConsumerWidget {
  final BigBlob blob;
  const _BlobRow({required this.blob});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final c = blob.commit;
    final path = blob.blob.path.isEmpty ? l.mntNoPath : blob.blob.path;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              formatBytes(blob.blob.size),
              style: AppFonts.mns(size: 12, color: t.textPrimary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(path, style: _body(t), overflow: TextOverflow.ellipsis),
                Text(
                  c == null ? l.mntNoCommit : '${c.shortSha} ${c.subject}',
                  style: _faint(t),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // The path and sha stay reachable however narrow the row gets.
    final tip = '$path\n${blob.blob.sha}';
    if (c == null) return Tooltip(message: tip, child: row);
    return Tooltip(
      message: '$tip\n${l.mntShowCommit}',
      child: InkWell(
        hoverColor: t.hover,
        // Closes the panel, so the selection lands in a graph that can be
        // seen. maybePop: the panel is not always on a route of its own.
        onTap: () {
          ref.read(selectedCommitProvider.notifier).state = c.sha;
          Navigator.of(context).maybePop();
        },
        child: row,
      ),
    );
  }
}

class _Branches extends ConsumerStatefulWidget {
  final String repoPath;
  const _Branches({required this.repoPath});

  @override
  ConsumerState<_Branches> createState() => _BranchesState();
}

class _BranchesState extends ConsumerState<_Branches> {
  final _selected = <String>{};

  Future<void> _delete(List<HygieneBranch> picked, String? trunk) async {
    final l = AppLocalizations.of(context);
    final forced = [
      for (final b in picked)
        if (b.needsForce) b.name,
    ];
    final body = [
      l.mntDeleteBody(picked.length),
      if (forced.isNotEmpty) ...[
        '',
        l.mntDeleteForce,
        for (final n in forced) '• $n',
      ],
    ].join('\n');
    final ok = await showConfirmDialog(
      context,
      title: l.mntDeleteTitle,
      body: body,
      confirmLabel: l.mntDeleteConfirm,
    );
    if (!ok || !mounted) return;
    await ref
        .read(repoActionsProvider(widget.repoPath))
        .deleteBranches(picked, trunk: trunk);
    if (!mounted) return;
    setState(_selected.clear);
    ref.invalidate(branchHygieneProvider(widget.repoPath));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final settings = ref.watch(settingsProvider);
    return ref
        .watch(branchHygieneProvider(widget.repoPath))
        .when(
          loading: _loading,
          error: (e, _) => _failed(context, e),
          data: (h) {
            // A worktree whose directory is gone still holds its branch until
            // it is pruned, which is the one thing that frees the branch.
            final vanished = {
              for (final w
                  in ref
                          .watch(worktreesProvider(widget.repoPath))
                          .valueOrNull ??
                      const [])
                if (w.prunable) w.path,
            };
            if (h.branches.isEmpty) {
              return Text(l.mntNoBranches, style: _faint(t));
            }
            final pickable = [
              for (final b in h.branches)
                if (b.selectable) b,
            ];
            // A branch deleted elsewhere since it was ticked is no longer
            // on offer, and must not be deleted on the strength of that tick.
            final picked = [
              for (final b in pickable)
                if (_selected.contains(b.name)) b,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.mntMergedInto(h.trunk ?? '—', staleBranchAge.inDays),
                  style: _faint(t),
                ),
                const SizedBox(height: 4),
                for (final b in h.branches)
                  _BranchRow(
                    branch: b,
                    holderVanished: vanished.contains(b.heldBy),
                    selected: _selected.contains(b.name),
                    date: formatCommitDate(
                      b.lastCommit,
                      format: settings.dateFormat,
                    ),
                    onChanged: b.selectable
                        ? (v) => setState(
                            () => v == true
                                ? _selected.add(b.name)
                                : _selected.remove(b.name),
                          )
                        : null,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed: pickable.isEmpty
                          ? null
                          : () => setState(
                              () => _selected.addAll([
                                for (final b in pickable) b.name,
                              ]),
                            ),
                      child: Text(l.mntSelectAll),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: t.danger),
                      onPressed: picked.isEmpty
                          ? null
                          : () => _delete(picked, h.trunk),
                      child: Text(l.mntDeleteSelected(picked.length)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}

class _BranchRow extends StatelessWidget {
  final HygieneBranch branch;

  /// The worktree holding [branch] no longer exists on disk.
  final bool holderVanished;
  final bool selected;
  final String date;
  final ValueChanged<bool?>? onChanged;

  const _BranchRow({
    required this.branch,
    this.holderVanished = false,
    required this.selected,
    required this.date,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tags = [
      if (branch.merged) l.mntTagMerged else l.mntTagStale,
      if (branch.gone) l.mntTagGone,
      date,
      if (branch.heldBy != null)
        holderVanished
            ? l.mntHeldByPrunable(branch.heldBy!)
            : l.mntHeldBy(branch.heldBy!),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          key: ValueKey('mt-branch-${branch.name}'),
          value: selected && onChanged != null,
          onChanged: onChanged,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  branch.name,
                  style: _body(
                    t,
                    color: onChanged == null ? t.textMuted : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 8,
                  children: [for (final s in tags) Text(s, style: _faint(t))],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Worktrees extends ConsumerWidget {
  final String repoPath;
  const _Worktrees({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(worktreesProvider(repoPath))
        .when(
          loading: _loading,
          error: (e, _) => _failed(context, e),
          data: (list) {
            final prunable = list.where((w) => w.prunable).length;
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  prunable == 0 ? l.mntNoPrunable : l.mntPrunable(prunable),
                  style: _body(t),
                ),
                if (prunable > 0)
                  OutlinedButton(
                    onPressed: () async {
                      final actions = ref.read(repoActionsProvider(repoPath));
                      final report = await actions.worktreePrune(dryRun: true);
                      if (!context.mounted) return;
                      if (await showPruneDialog(context, report)) {
                        await actions.worktreePrune();
                      }
                    },
                    child: Text(l.mntPrune),
                  ),
              ],
            );
          },
        );
  }
}

class _Reflog extends ConsumerWidget {
  final String repoPath;
  const _Reflog({required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ref
        .watch(reflogExpiryProvider(repoPath))
        .when(
          loading: _loading,
          error: (e, _) => _failed(context, e),
          data: (n) => Text(l.mntReflogExpiry(n), style: _body(context.tokens)),
        );
  }
}

class _Housekeeping extends ConsumerStatefulWidget {
  final String repoPath;
  const _Housekeeping({required this.repoPath});

  @override
  ConsumerState<_Housekeeping> createState() => _HousekeepingState();
}

class _HousekeepingState extends ConsumerState<_Housekeeping> {
  String? _change;

  Future<void> _run({
    required String title,
    required String body,
    required Future<bool> Function(RepoActions) op,
  }) async {
    final l = AppLocalizations.of(context);
    final path = widget.repoPath;
    final ok = await showConfirmDialog(
      context,
      title: title,
      body: body,
      confirmLabel: l.mntRun,
    );
    if (!ok || !mounted) return;
    final before = ref.read(maintenanceSizeProvider(path)).valueOrNull;
    final finished = await op(ref.read(repoActionsProvider(path)));
    if (!finished || !mounted) return;
    ref
      ..invalidate(maintenanceSizeProvider(path))
      ..invalidate(reflogExpiryProvider(path))
      ..invalidate(worktreesProvider(path));
    setState(() => _change = null);
    try {
      final after = await ref.read(maintenanceSizeProvider(path).future);
      if (!mounted || before == null) return;
      // Formatted, not raw bytes: a run that freed a few bytes of a
      // gigabyte has not changed anything the user can see.
      final from = formatBytes(before.disk.totalBytes);
      final to = formatBytes(after.disk.totalBytes);
      if (from == to) return;
      setState(() => _change = l.mntSizeChange(from, to));
    } on Object {
      // The storage section shows the read failure itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.mntHousekeepingHint, style: _faint(t)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: () => _run(
                title: l.mntGcTitle,
                body: l.mntGcBody,
                op: (a) => a.runGc(),
              ),
              child: Text(l.mntRunGc),
            ),
            OutlinedButton(
              onPressed: () => _run(
                title: l.mntMaintenanceTitle,
                body: l.mntMaintenanceBody,
                op: (a) => a.runMaintenance(),
              ),
              child: Text(l.mntRunMaintenance),
            ),
          ],
        ),
        if (_change != null) ...[
          const SizedBox(height: 8),
          Text(_change!, style: _body(t)),
        ],
      ],
    );
  }
}
