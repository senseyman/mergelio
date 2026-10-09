import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/diff.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/models.dart';
import 'compare_target.dart';
import 'diff_target.dart';
import 'diff_view_options.dart';

/// A loaded diff for the sheet. [editable] enables the staging gutter/buttons.
/// [staged] flips their direction: when true the view shows already-staged
/// changes and the actions unstage (reverse patch); when false they stage.
/// [whitespaceIgnored] marks hunks read blind to whitespace; [whitespaceOnly]
/// marks an empty read whose file did change, only in whitespace.
class DiffDoc {
  final List<FileDiff> files;
  final bool editable;
  final bool staged;
  final bool whitespaceIgnored;
  final bool whitespaceOnly;
  const DiffDoc({
    required this.files,
    required this.editable,
    required this.staged,
    this.whitespaceIgnored = false,
    this.whitespaceOnly = false,
  });

  bool get isEmpty => files.every((f) => f.hunks.isEmpty && !f.binary);
  bool get isBinary => files.any((f) => f.binary);

  /// Whether hunks and lines can be staged, unstaged or discarded. A hunk read
  /// with whitespace ignored leaves out edits the index still has, so a patch
  /// built from it would not apply — or worse, would apply wrongly.
  bool get canApplyPatches => editable && !whitespaceIgnored;
}

/// Whether [files] hold anything to show. A rename counts even with no
/// content change: it is a change, and treating it as nothing would fall
/// through to showing the new name as an untracked, wholly added file.
bool _hasChange(List<FileDiff> files) => files.any(
  (f) => f.hunks.isNotEmpty || f.binary || f.status == GitChange.renamed,
);

/// Loads and parses the diff for [target]. For the working tree it shows the
/// side selected by [DiffTarget.staged]; a commit diff is read-only.
final diffDocumentProvider = FutureProvider.family
    .autoDispose<DiffDoc, DiffTarget>((ref, target) async {
      final reader = GitReader(ref.watch(gitServiceProvider), target.repoPath);
      final options = ref.watch(diffViewOptionsProvider);
      // Widening the context is what turns the "changed regions" view into the
      // whole-file view; null keeps git's default of 3 lines.
      final ctx = options.contextArg(wholeFile: target.wholeFile);
      final ws = options.whitespace;

      DiffDoc doc(
        List<FileDiff> files, {
        required bool editable,
        required bool staged,
        bool whitespaceOnly = false,
      }) => DiffDoc(
        files: files,
        editable: editable,
        staged: staged,
        whitespaceIgnored: options.ignoresWhitespace,
        whitespaceOnly: whitespaceOnly,
      );

      // A read-only diff, with whitespace-only kept apart from no change.
      // With whitespace ignored an empty read is ambiguous — the file may
      // have changed only its mode — so it is read again with whitespace
      // shown before saying the change was whitespace.
      Future<DiffDoc> readOnly(
        Future<String> Function(DiffWhitespace) read,
      ) async {
        final files = parseUnifiedDiff(await read(ws));
        final whitespaceOnly =
            options.ignoresWhitespace &&
            !_hasChange(files) &&
            _hasChange(parseUnifiedDiff(await read(DiffWhitespace.show)));
        return doc(
          files,
          editable: false,
          staged: false,
          whitespaceOnly: whitespaceOnly,
        );
      }

      // Two revisions: what it takes to get from one to the other. Read-only,
      // like a commit diff — there is no index to stage into.
      if (target.isComparison) {
        // The list of files follows the refs as they move; an open diff of one
        // of those files has to follow them too, or the panel and the sheet
        // end up describing different states.
        followRefMoves(
          ref,
          repoPath: target.repoPath,
          from: target.baseRev!,
          to: target.commitSha!,
        );
        return readOnly(
          (w) => reader.compareDiff(
            target.baseRev!,
            target.commitSha!,
            target.path,
            context: ctx,
            origPath: target.origPath,
            whitespace: w,
          ),
        );
      }

      if (target.commitSha != null) {
        return readOnly(
          (w) => reader.commitDiff(
            target.commitSha!,
            target.path,
            context: ctx,
            origPath: target.origPath,
            whitespace: w,
          ),
        );
      }

      // One side of the working tree, or null when it holds no change. With
      // whitespace ignored an empty read is ambiguous: re-read that side with
      // whitespace shown, so a whitespace-only edit keeps its side instead of
      // falling through to the next one — and at the end of the chain, to the
      // untracked view that would render the whole file as added.
      Future<DiffDoc?> side(
        Future<String> Function(DiffWhitespace) read, {
        required bool staged,
      }) async {
        final files = parseUnifiedDiff(await read(ws));
        if (_hasChange(files)) {
          return doc(files, editable: true, staged: staged);
        }
        if (!options.ignoresWhitespace) return null;
        final shown = parseUnifiedDiff(await read(DiffWhitespace.show));
        if (!_hasChange(shown)) return null;
        return doc(files, editable: true, staged: staged, whitespaceOnly: true);
      }

      Future<DiffDoc?> stagedSide() => side(
        (w) => reader.stagedDiff(
          target.path,
          context: ctx,
          origPath: target.origPath,
          whitespace: w,
        ),
        staged: true,
      );

      // Staged side requested: show the index→HEAD diff. Only fall through to
      // the unstaged branch when nothing is staged (e.g. a stale target).
      if (target.staged) {
        final staged = await stagedSide();
        if (staged != null) return staged;
      }

      final unstaged = await side(
        (w) => reader.workingDiff(target.path, context: ctx, whitespace: w),
        staged: false,
      );
      if (unstaged != null) return unstaged;
      final staged = await stagedSide();
      if (staged != null) return staged;
      // No tracked diff: an untracked file shows its content as additions.
      // An all-added read has nothing for a whitespace flag to hide, so it is
      // read exactly and its lines stay stageable.
      final untracked = parseUnifiedDiff(
        await reader.untrackedDiff(target.path, context: ctx),
      );
      return DiffDoc(files: untracked, editable: true, staged: false);
    });
