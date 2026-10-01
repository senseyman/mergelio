import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/maintenance.dart';
import '../../l10n/gen/app_localizations.dart';
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
      title: AppLocalizations.of(context).mtTitle,
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
          title: l.mtStorage,
          child: _Storage(repoPath: path),
        ),
        _Section(
          title: l.mtBlobs,
          child: _Blobs(repoPath: path),
        ),
        _Section(
          title: l.mtBranches,
          child: _Branches(repoPath: path),
        ),
        _Section(
          title: l.mtWorktrees,
          child: _Worktrees(repoPath: path),
        ),
        _Section(
          title: l.mtReflog,
          child: _Reflog(repoPath: path),
        ),
        _Section(
          title: l.mtHousekeeping,
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

Widget _failed(BuildContext context, Object error) => Text(
  AppLocalizations.of(context).mtReadFailed('$error'),
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
                l.mtStorageTotal(formatBytes(s.disk.totalBytes)),
                style: _body(t).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _SizeRow(
                label: l.mtPacks,
                bytes: s.disk.packBytes,
                detail: l.mtPackCount(s.counts.packCount),
              ),
              _SizeRow(
                label: l.mtLoose,
                bytes: s.disk.looseBytes,
                detail: l.mtLooseCount(s.counts.looseCount),
              ),
              _SizeRow(label: l.mtLfs, bytes: s.disk.lfsBytes),
              _SizeRow(label: l.mtOther, bytes: s.disk.otherBytes),
              const SizedBox(height: 4),
              Text(l.mtStorageNote, style: _faint(t)),
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
              Text(l.mtScanning, style: _body(t))
            else if (scannedAt != null)
              Text(
                l.mtScannedAt(
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
              Text(l.mtBlobsIntro, style: _body(t)),
            if (s.scanning)
              TextButton(onPressed: ctl.cancel, child: Text(l.cancel))
            else
              OutlinedButton(
                onPressed: ctl.scan,
                child: Text(result == null ? l.mtScan : l.mtRescan),
              ),
          ],
        ),
        if (s.scanning) _loading(),
        if (s.stale && !s.scanning) ...[
          const SizedBox(height: 4),
          Text(l.mtScanStale, style: _body(t, color: t.warning)),
        ],
        if (s.error != null) ...[
          const SizedBox(height: 4),
          Text(l.mtScanFailed(s.error!), style: _body(t, color: t.danger)),
        ],
        if (result != null) ...[
          const SizedBox(height: 8),
          if (result.blobs.isEmpty) Text(l.mtNoBlobs, style: _faint(t)),
          for (final b in result.blobs) _BlobRow(blob: b),
        ],
      ],
    );
  }
}

class _BlobRow extends StatelessWidget {
  final BigBlob blob;
  const _BlobRow({required this.blob});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final c = blob.commit;
    final path = blob.blob.path.isEmpty ? l.mtNoPath : blob.blob.path;
    return Padding(
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
            child: Tooltip(
              message: '$path\n${blob.blob.sha}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(path, style: _body(t), overflow: TextOverflow.ellipsis),
                  Text(
                    c == null ? l.mtNoCommit : '${c.shortSha} ${c.subject}',
                    style: _faint(t),
                    overflow: TextOverflow.ellipsis,
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
      l.mtDeleteBody(picked.length),
      if (forced.isNotEmpty) ...[
        '',
        l.mtDeleteForce,
        for (final n in forced) '• $n',
      ],
    ].join('\n');
    final ok = await showConfirmDialog(
      context,
      title: l.mtDeleteTitle,
      body: body,
      confirmLabel: l.mtDeleteConfirm,
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
            if (h.branches.isEmpty) {
              return Text(l.mtNoBranches, style: _faint(t));
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
                Text(l.mtMergedInto(h.trunk ?? '—'), style: _faint(t)),
                const SizedBox(height: 4),
                for (final b in h.branches)
                  _BranchRow(
                    branch: b,
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
                      child: Text(l.mtSelectAll),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: t.danger),
                      onPressed: picked.isEmpty
                          ? null
                          : () => _delete(picked, h.trunk),
                      child: Text(l.mtDeleteSelected(picked.length)),
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
  final bool selected;
  final String date;
  final ValueChanged<bool?>? onChanged;

  const _BranchRow({
    required this.branch,
    required this.selected,
    required this.date,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final tags = [
      if (branch.merged) l.mtTagMerged else l.mtTagStale,
      if (branch.gone) l.mtTagGone,
      date,
      if (branch.heldBy != null) l.mtHeldBy(branch.heldBy!),
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
                  prunable == 0 ? l.mtNoPrunable : l.mtPrunable(prunable),
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
                    child: Text(l.mtPrune),
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
          data: (n) => Text(l.mtReflogExpiry(n), style: _body(context.tokens)),
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
  String? _output;
  String? _change;

  Future<void> _run({
    required String title,
    required String body,
    required Future<String?> Function(RepoActions) op,
  }) async {
    final l = AppLocalizations.of(context);
    final path = widget.repoPath;
    final ok = await showConfirmDialog(
      context,
      title: title,
      body: body,
      confirmLabel: l.mtRun,
    );
    if (!ok || !mounted) return;
    final before = ref.read(maintenanceSizeProvider(path)).valueOrNull;
    final out = await op(ref.read(repoActionsProvider(path)));
    if (out == null || !mounted) return;
    ref
      ..invalidate(maintenanceSizeProvider(path))
      ..invalidate(reflogExpiryProvider(path))
      ..invalidate(worktreesProvider(path));
    setState(() {
      _output = out.trim();
      _change = null;
    });
    try {
      final after = await ref.read(maintenanceSizeProvider(path).future);
      if (!mounted || before == null) return;
      setState(
        () => _change = l.mtSizeChange(
          formatBytes(before.disk.totalBytes),
          formatBytes(after.disk.totalBytes),
        ),
      );
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
        Text(l.mtHousekeepingHint, style: _faint(t)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: () => _run(
                title: l.mtGcTitle,
                body: l.mtGcBody,
                op: (a) => a.runGc(),
              ),
              child: Text(l.mtRunGc),
            ),
            OutlinedButton(
              onPressed: () => _run(
                title: l.mtMaintenanceTitle,
                body: l.mtMaintenanceBody,
                op: (a) => a.runMaintenance(),
              ),
              child: Text(l.mtRunMaintenance),
            ),
          ],
        ),
        if (_change != null) ...[
          const SizedBox(height: 8),
          Text(_change!, style: _body(t)),
        ],
        if (_output != null && _output!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.mtOutput, style: _faint(t)),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _output!,
                style: AppFonts.mns(size: 11, color: t.textMuted),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
