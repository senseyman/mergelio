import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/file_edit.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_drafts.dart';
import '../../state/diff_target.dart';
import '../../state/file_editor.dart';
import '../../state/repo_actions.dart';
import '../../state/unsaved_guard.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';

/// Asks about unsaved diff-sheet edits before their repository is closed or
/// the app quits. The edits outlive the sheet — a tab switch sets them aside —
/// so the question cannot be left to the sheet; this sits above every
/// repository for as long as the app runs and keeps one guard per repository
/// that has any.
class DiffDraftGuard extends ConsumerStatefulWidget {
  final Widget child;
  const DiffDraftGuard({super.key, required this.child});

  @override
  ConsumerState<DiffDraftGuard> createState() => _DiffDraftGuardState();
}

class _DiffDraftGuardState extends ConsumerState<DiffDraftGuard> {
  final _drops = <String, DropGuard>{};

  /// Held rather than read through `ref`, which is off limits by the time
  /// this widget is being torn down.
  late final UnsavedGuards _guards;

  @override
  void initState() {
    super.initState();
    _guards = ref.read(unsavedGuardsProvider);
    // NUL cannot appear in a path, so it keeps the joined key unambiguous.
    ref.listenManual(
      diffDraftsProvider.select(
        (d) => {for (final t in d.keys) t.repoPath}.join('\u0000'),
      ),
      (_, _) => _sync(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    for (final drop in _drops.values) {
      drop();
    }
    super.dispose();
  }

  void _sync() {
    final repos = {
      for (final t in ref.read(diffDraftsProvider).keys) t.repoPath,
    };
    for (final repo in [..._drops.keys]) {
      if (!repos.contains(repo)) _drops.remove(repo)!();
    }
    for (final repo in repos) {
      _drops[repo] ??= _guards.register(
        repo,
        () => _confirm(repo),
        // A switch to Files and back leaves the edits where they were.
        survivesViewSwitch: true,
      );
    }
  }

  /// One prompt for every file edited in [repo], like the Files-mode editors.
  Future<bool> _confirm(String repo) async {
    final targets = draftTargetsIn(ref.read(diffDraftsProvider), repo);
    if (targets.isEmpty || !mounted) return true;
    final choice = await showUnsavedDialog(
      context,
      paths: [for (final t in targets) t.path],
    );
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        targets.forEach(_forget);
        return true;
      case UnsavedChoice.save:
        for (final target in targets) {
          if (!await _save(target)) return false;
          _forget(target);
        }
        return true;
    }
  }

  /// Writes the draft the way the editor's own save would, outside-change
  /// check included.
  Future<bool> _save(DiffTarget target) async {
    final draft = ref.read(diffDraftsProvider)[target];
    if (draft == null) return true;
    final onDisk = File('${target.repoPath}/${target.path}');
    if (await fileChangedSince(onDisk, draft.baseline.loadedAt)) {
      if (!mounted) return false;
      final l = AppLocalizations.of(context);
      final ok = await confirmDestructive(
        ref,
        context,
        title: l.commonFileChangedOnDisk,
        body: l.fteConflictBody(target.path),
        confirmLabel: l.commonOverwrite,
      );
      if (!ok) return false;
    }
    if (!mounted) return false;
    return ref
        .read(repoActionsProvider(target.repoPath))
        .saveFileText(target.path, draft.text);
  }

  /// Drops the draft, and the sheet with it if that is where it is showing —
  /// in whichever view or side.
  void _forget(DiffTarget target) {
    if (!mounted) return;
    ref.read(diffDraftsProvider.notifier).drop(target);
    final open = ref.read(diffTargetProvider);
    if (open != null && editsSameFile(open, target)) {
      ref.read(diffEditorDirtyProvider.notifier).state = false;
      ref.read(diffEditingProvider.notifier).state = null;
      ref.read(diffTargetProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
