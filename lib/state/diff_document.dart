import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/diff.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'diff_target.dart';

/// A loaded diff for the sheet. [editable] enables the staging gutter/buttons.
/// [staged] flips their direction: when true the view shows already-staged
/// changes and the actions unstage (reverse patch); when false they stage.
class DiffDoc {
  final List<FileDiff> files;
  final bool editable;
  final bool staged;
  const DiffDoc({
    required this.files,
    required this.editable,
    required this.staged,
  });

  bool get isEmpty => files.every((f) => f.hunks.isEmpty && !f.binary);
  bool get isBinary => files.any((f) => f.binary);
}

/// Loads and parses the diff for [target]. For the working tree it shows the
/// side selected by [DiffTarget.staged]; a commit diff is read-only.
final diffDocumentProvider = FutureProvider.family
    .autoDispose<DiffDoc, DiffTarget>((ref, target) async {
      final reader = GitReader(ref.watch(gitServiceProvider), target.repoPath);
      // Widening the context is what turns the "changed regions" view into the
      // whole-file view; null keeps git's default of 3 lines.
      final ctx = target.wholeFile ? kWholeFileContext : null;

      if (target.commitSha != null) {
        final raw = await reader.commitDiff(
          target.commitSha!,
          target.path,
          context: ctx,
        );
        return DiffDoc(
          files: parseUnifiedDiff(raw),
          editable: false,
          staged: false,
        );
      }

      // Staged side requested: show the index→HEAD diff. Only fall through to
      // the unstaged branch when nothing is staged (e.g. a stale target).
      if (target.staged) {
        final onlyStaged = parseUnifiedDiff(
          await reader.stagedDiff(target.path, context: ctx),
        );
        if (onlyStaged.any((f) => f.hunks.isNotEmpty || f.binary)) {
          return DiffDoc(files: onlyStaged, editable: true, staged: true);
        }
      }

      final unstaged = parseUnifiedDiff(
        await reader.workingDiff(target.path, context: ctx),
      );
      if (unstaged.any((f) => f.hunks.isNotEmpty || f.binary)) {
        return DiffDoc(files: unstaged, editable: true, staged: false);
      }
      final staged = parseUnifiedDiff(
        await reader.stagedDiff(target.path, context: ctx),
      );
      if (staged.any((f) => f.hunks.isNotEmpty || f.binary)) {
        return DiffDoc(files: staged, editable: true, staged: true);
      }
      // No tracked diff: an untracked file shows its content as additions.
      final untracked = parseUnifiedDiff(
        await reader.untrackedDiff(target.path, context: ctx),
      );
      return DiffDoc(files: untracked, editable: true, staged: false);
    });
