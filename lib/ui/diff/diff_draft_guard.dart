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
    ref.listenManual(
      diffDraftsProvider.select((d) => d.keys.join('\n')),
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
    final repos = ref.read(diffDraftsProvider).keys.toSet();
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

  Future<bool> _confirm(String repo) async {
    final draft = ref.read(diffDraftsProvider)[repo];
    if (draft == null || !mounted) return true;
    final choice = await showUnsavedDialog(context, paths: [draft.target.path]);
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        _forget(draft.target);
        return true;
      case UnsavedChoice.save:
        if (!await _save(draft)) return false;
        _forget(draft.target);
        return true;
    }
  }

  /// Writes the draft the way the editor's own save would, outside-change
  /// check included.
  Future<bool> _save(DiffDraft draft) async {
    final target = draft.target;
    final onDisk = File('${target.repoPath}/${target.path}');
    if (await fileChangedSince(onDisk, draft.editor.baseline.loadedAt)) {
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
        .saveFileText(target.path, draft.editor.text);
  }

  /// Drops the draft, and the sheet with it if that is where it is showing.
  void _forget(DiffTarget target) {
    if (!mounted) return;
    ref.read(diffDraftsProvider.notifier).drop(target.repoPath);
    if (ref.read(diffTargetProvider) == target) {
      ref.read(diffEditorDirtyProvider.notifier).state = false;
      ref.read(diffEditingProvider.notifier).state = null;
      ref.read(diffTargetProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
