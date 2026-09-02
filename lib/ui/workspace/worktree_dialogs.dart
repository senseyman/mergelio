import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/worktree.dart';
import '../../domain/path_key.dart';
import '../../l10n/gen/app_localizations.dart';
import '../common/dialogs.dart';

/// What the Add dialog collected. Exactly one of [newBranch], [existingBranch]
/// or [detach] describes what the new worktree checks out.
typedef AddWorktreeData = ({
  String path,
  String? newBranch,
  String? startPoint,
  String? existingBranch,
  bool detach,
  bool openTab,
});

enum _AddMode { newBranch, existing, detached }

/// Collects a location and a checkout target for a new worktree. Returns null
/// if cancelled.
Future<AddWorktreeData?> showAddWorktreeDialog(
  BuildContext context, {
  required String repoPath,
  required List<Worktree> existing,
  required List<String> branches,
  required String? currentBranch,
  bool Function(String path)? isNonEmptyDir,
  bool hasSubmodules = false,
}) => showAppModal<AddWorktreeData>(
  context: context,
  title: AppLocalizations.of(context).wtAdd,
  icon: Icons.dashboard_outlined,
  width: 520,
  body: _AddWorktreeBody(
    repoPath: repoPath,
    existing: existing,
    branches: branches,
    currentBranch: currentBranch,
    isNonEmptyDir: isNonEmptyDir ?? _isNonEmptyDirOnDisk,
    hasSubmodules: hasSubmodules,
  ),
);

/// Real filesystem check used in production. Widget tests inject a stub via
/// [showAddWorktreeDialog]'s `isNonEmptyDir` so `_existsError` never touches
/// disk during a pump.
bool _isNonEmptyDirOnDisk(String path) {
  final dir = Directory(path);
  return dir.existsSync() && dir.listSync().isNotEmpty;
}

class _AddWorktreeBody extends StatefulWidget {
  final String repoPath;
  final List<Worktree> existing;
  final List<String> branches;
  final String? currentBranch;
  final bool Function(String path) isNonEmptyDir;
  final bool hasSubmodules;

  const _AddWorktreeBody({
    required this.repoPath,
    required this.existing,
    required this.branches,
    required this.currentBranch,
    required this.isNonEmptyDir,
    required this.hasSubmodules,
  });

  @override
  State<_AddWorktreeBody> createState() => _AddWorktreeBodyState();
}

class _AddWorktreeBodyState extends State<_AddWorktreeBody> {
  final _path = TextEditingController();
  final _branch = TextEditingController();
  final _startPoint = TextEditingController();
  // Once the user edits the location by hand, stop deriving it from the branch.
  bool _pathEdited = false;
  _AddMode _mode = _AddMode.newBranch;
  String? _existingBranch;
  bool _openTab = true;

  @override
  void initState() {
    super.initState();
    _startPoint.text = widget.currentBranch ?? 'HEAD';
    _existingBranch = widget.branches
        .where((b) => worktreeHolding(widget.existing, b) == null)
        .firstOrNull;
  }

  @override
  void dispose() {
    _path.dispose();
    _branch.dispose();
    _startPoint.dispose();
    super.dispose();
  }

  void _onBranchChanged(String v) {
    if (!_pathEdited) {
      _path.text = suggestWorktreePath(widget.repoPath, v.trim());
    }
    setState(() {});
  }

  /// The branch this worktree would check out, for path suggestion purposes.
  String get _targetBranch => switch (_mode) {
    _AddMode.newBranch => _branch.text.trim(),
    _AddMode.existing => _existingBranch ?? '',
    _AddMode.detached => 'detached',
  };

  String? get _pathError => validateWorktreeDestination(
    destination: _path.text,
    repoPath: widget.repoPath,
    existing: widget.existing,
  );

  String? get _branchError {
    if (_mode != _AddMode.newBranch) return null;
    final illegal = validateNewBranchName(_branch.text);
    if (illegal != null) return illegal;
    // git would refuse this too, but only after creating nothing and leaving
    // the user to read its message; the branch list is already here.
    return widget.branches.contains(_branch.text.trim())
        ? AppLocalizations.of(context).wtBranchExists
        : null;
  }

  /// Existing directories are only acceptable when empty — git refuses
  /// otherwise, and saying so here spares the round trip. The actual check is
  /// injected (real filesystem in production, a stub in tests) so this getter
  /// never touches disk itself.
  String? get _existsError {
    final p = _path.text.trim();
    if (p.isEmpty) return null;
    return widget.isNonEmptyDir(p)
        ? AppLocalizations.of(context).wtDirNotEmpty
        : null;
  }

  bool get _valid =>
      _pathError == null &&
      _branchError == null &&
      _existsError == null &&
      (_mode != _AddMode.existing || _existingBranch != null);

  Future<void> _browse() async {
    final chosen = await getDirectoryPath();
    if (chosen == null) return;
    setState(() {
      _pathEdited = true;
      _path.text = chosen;
    });
  }

  void _submit() {
    // An empty start point is no start point: passed on as '' it would reach
    // git as an argument of its own and be rejected as an invalid reference,
    // where leaving it out lets git default to HEAD.
    final start = _startPoint.text.trim();
    Navigator.of(context).pop((
      path: _path.text.trim(),
      newBranch: _mode == _AddMode.newBranch ? _branch.text.trim() : null,
      startPoint: _mode == _AddMode.existing || start.isEmpty ? null : start,
      existingBranch: _mode == _AddMode.existing ? _existingBranch : null,
      detach: _mode == _AddMode.detached,
      openTab: _openTab,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final err = _pathError ?? _existsError ?? _branchError;

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.rButton),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.wtLocation, style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('worktree-path'),
                controller: _path,
                decoration: deco('${widget.repoPath}-feature'),
                onChanged: (_) => setState(() => _pathEdited = true),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _browse, child: Text(l.wtBrowse)),
          ],
        ),
        const SizedBox(height: 14),
        RadioGroup<_AddMode>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
          child: Column(
            children: [
              RadioListTile<_AddMode>(
                key: const Key('worktree-mode-new'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _AddMode.newBranch,
                title: Row(
                  children: [
                    Text(l.wtNewBranch, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('worktree-new-branch'),
                        controller: _branch,
                        enabled: _mode == _AddMode.newBranch,
                        decoration: deco('feat/login'),
                        onChanged: _onBranchChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(l.wtFrom, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: const Key('worktree-start-point'),
                        controller: _startPoint,
                        enabled: _mode != _AddMode.existing,
                        decoration: deco('main'),
                      ),
                    ),
                  ],
                ),
              ),
              RadioListTile<_AddMode>(
                key: const Key('worktree-mode-existing'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _AddMode.existing,
                title: Row(
                  children: [
                    Text(
                      l.wtExistingBranch,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('worktree-existing-branch'),
                        initialValue: _existingBranch,
                        isExpanded: true,
                        decoration: deco(''),
                        items: [
                          for (final b in widget.branches)
                            DropdownMenuItem(
                              value: b,
                              // A branch checked out elsewhere cannot be attached:
                              // git allows one worktree per branch.
                              enabled:
                                  worktreeHolding(widget.existing, b) == null,
                              child: Row(
                                children: [
                                  Text(b, style: const TextStyle(fontSize: 13)),
                                  if (worktreeHolding(widget.existing, b) !=
                                      null) ...[
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        l.wtHeldBy(
                                          worktreeHolding(
                                            widget.existing,
                                            b,
                                          )!.name,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: t.textFaint,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                        onChanged: _mode == _AddMode.existing
                            ? (v) => setState(() {
                                _existingBranch = v;
                                if (!_pathEdited && v != null) {
                                  _path.text = suggestWorktreePath(
                                    widget.repoPath,
                                    v,
                                  );
                                }
                              })
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              RadioListTile<_AddMode>(
                key: const Key('worktree-mode-detached'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _AddMode.detached,
                title: Text(
                  l.wtDetachedAt,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (widget.hasSubmodules)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              // `worktree add` leaves them uninitialised, and initialising
              // them here is out of scope — so say it rather than let the new
              // worktree look broken.
              l.wtSubmodulesNote,
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _openTab,
          onChanged: (v) => setState(() => _openTab = v ?? true),
          title: Text(
            l.wtOpenInNewTab,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
        ),
        if (err != null) const SizedBox(height: 6),
        if (err != null)
          Text(err, style: TextStyle(color: t.danger, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid && _targetBranch.isNotEmpty ? _submit : null,
              child: Text(l.wtAdd),
            ),
          ],
        ),
      ],
    );
  }
}

/// First-stage removal confirmation. Names what will be deleted; the actual
/// refusal-and-force path is [showForceRemoveDialog].
Future<bool> showRemoveWorktreeDialog(BuildContext context, Worktree w) async {
  final l = AppLocalizations.of(context);
  final answer = await showAppModal<bool>(
    context: context,
    title: l.wtRemoveTitle,
    icon: Icons.delete_outline,
    width: 460,
    body: _ConfirmBody(
      lines: [
        w.path,
        if (w.branch != null) l.wtCheckedOutBranch(w.branch!),
        l.wtDirDeleted,
      ],
      confirmLabel: l.wtRemove,
    ),
  );
  return answer ?? false;
}

/// Second stage: git refused, so show exactly why and offer the override.
Future<bool> showForceRemoveDialog(
  BuildContext context,
  Worktree w,
  String gitMessage,
) async {
  final l = AppLocalizations.of(context);
  final answer = await showAppModal<bool>(
    context: context,
    title: l.wtHasChangesTitle,
    icon: Icons.warning_amber_outlined,
    width: 480,
    body: _ConfirmBody(
      lines: [w.path, gitMessage, l.wtForcingDiscards],
      confirmLabel: l.wtForceRemove,
    ),
  );
  return answer ?? false;
}

/// Destination for `git worktree move`. Returns null when cancelled.
///
/// Runs the destination through the same [validateWorktreeDestination] the Add
/// dialog uses: a move into the repository, onto the repository itself, or onto
/// another worktree is refused before git is asked, and the reason is shown
/// while the user is still typing.
Future<String?> showMoveWorktreeDialog(
  BuildContext context,
  Worktree w, {
  required String repoPath,
  required List<Worktree> existing,
}) => showAppModal<String>(
  context: context,
  title: AppLocalizations.of(context).wtMoveTitle,
  icon: Icons.drive_file_move_outlined,
  width: 480,
  body: _MoveWorktreeBody(worktree: w, repoPath: repoPath, existing: existing),
);

class _MoveWorktreeBody extends StatefulWidget {
  final Worktree worktree;
  final String repoPath;
  final List<Worktree> existing;
  const _MoveWorktreeBody({
    required this.worktree,
    required this.repoPath,
    required this.existing,
  });

  @override
  State<_MoveWorktreeBody> createState() => _MoveWorktreeBodyState();
}

class _MoveWorktreeBodyState extends State<_MoveWorktreeBody> {
  late final _path = TextEditingController(text: widget.worktree.path);

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  /// The worktree being moved is excluded from the collision check — its own
  /// current location is not "already taken" by something else. Standing still
  /// is caught separately, so the message says what actually happened.
  String? get _error {
    final to = _path.text.trim();
    if (to.isNotEmpty && samePath(to, widget.worktree.path)) {
      return AppLocalizations.of(context).wtAlreadyThere;
    }
    return validateWorktreeDestination(
      destination: to,
      repoPath: widget.repoPath,
      existing: [
        for (final e in widget.existing)
          if (!samePath(e.path, widget.worktree.path)) e,
      ],
    );
  }

  void _submit() {
    if (_error != null) return;
    Navigator.of(context).pop(_path.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final err = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.wtNewLocationFor(widget.worktree.name),
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('worktree-move-path'),
          controller: _path,
          autofocus: true,
          style: TextStyle(color: t.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        if (err != null) ...[
          const SizedBox(height: 6),
          Text(err, style: TextStyle(color: t.danger, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: err == null ? _submit : null,
              child: Text(l.wtMove),
            ),
          ],
        ),
      ],
    );
  }
}

/// What to do when the branch the user picked is checked out elsewhere.
enum CollisionChoice { openWorktree, checkoutAnyway, cancel }

/// Git allows one worktree per branch. Rather than surfacing its refusal after
/// the fact, offer the two things the user actually wants: go to where the
/// branch already is, or override.
Future<CollisionChoice> showWorktreeCollisionDialog(
  BuildContext context, {
  required String branch,
  required Worktree holder,
}) async {
  final choice = await showAppModal<CollisionChoice>(
    context: context,
    title: AppLocalizations.of(context).wtAlreadyCheckedOut,
    icon: Icons.dashboard_outlined,
    width: 500,
    body: _CollisionBody(branch: branch, holder: holder),
  );
  return choice ?? CollisionChoice.cancel;
}

class _CollisionBody extends StatelessWidget {
  final String branch;
  final Worktree holder;
  const _CollisionBody({required this.branch, required this.holder});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.wtCheckedOutInWorktreeAt(branch),
          style: TextStyle(color: t.textPrimary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(holder.path, style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 10),
        Text(
          l.wtTwoPlacesWarning,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(CollisionChoice.cancel),
              child: Text(l.cancel),
            ),
            // Deliberately not the default action.
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(CollisionChoice.checkoutAnyway),
              child: Text(l.wtCheckoutAnyway),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(CollisionChoice.openWorktree),
              child: Text(l.wtOpenWorktree),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shows git's dry-run report before pruning for real.
Future<bool> showPruneDialog(BuildContext context, String report) async {
  final answer = await showAppModal<bool>(
    context: context,
    title: AppLocalizations.of(context).wtPruneTitle,
    icon: Icons.cleaning_services_outlined,
    width: 560,
    body: _PruneBody(report: report),
  );
  return answer ?? false;
}

class _ConfirmBody extends StatelessWidget {
  final List<String> lines;
  final String confirmLabel;
  const _ConfirmBody({required this.lines, required this.confirmLabel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in lines) ...[
          Text(l, style: TextStyle(color: t.textPrimary, fontSize: 13)),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _PruneBody extends StatelessWidget {
  final String report;
  const _PruneBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final empty = report.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          empty ? l.wtNothingToPrune : l.wtEntriesWillBeRemoved,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        if (!empty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              // Git's own wording, shown as-is: parsing it would only add a
              // way to be wrong about what is about to happen.
              child: Text(
                report.trimRight(),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: empty ? null : () => Navigator.of(context).pop(true),
              child: Text(l.wtPrune),
            ),
          ],
        ),
      ],
    );
  }
}
