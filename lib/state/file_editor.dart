import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/file_edit.dart';
import 'diff_target.dart';

/// The working-tree file the diff sheet is currently editing, or null when the
/// sheet is showing a diff. Holding the target rather than a flag means moving
/// to another file — or to a commit — drops out of edit mode on its own.
final diffEditingProvider = StateProvider<DiffTarget?>((_) => null);

/// Whether the open editor holds text that has not been written to disk, so
/// anything that would close the editor can offer to keep it instead.
final diffEditorDirtyProvider = StateProvider<bool>((_) => false);

/// A working-tree file loaded for in-place editing, or the reason it cannot be.
class EditableFile {
  final String text;

  /// The file's mtime when it was read, so a write from outside the app can be
  /// spotted before saving over it.
  final DateTime? loadedAt;
  final String? blocker;
  const EditableFile({this.text = '', this.loadedAt, this.blocker});

  bool get canEdit => blocker == null;
}

/// Reads the working-tree file behind [target] for editing.
final editableFileProvider = FutureProvider.family
    .autoDispose<EditableFile, DiffTarget>((ref, target) async {
      if (!isRepoRelativePath(target.path)) {
        return const EditableFile(
          blocker: 'This file is not in the repository',
        );
      }
      final file = File('${target.repoPath}/${target.path}');
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      // Sniff the first block only, so an oversized file is not read whole
      // just to be turned down.
      final head = exists && size > 0
          ? await file
                .openRead(0, size < sniffBytes ? size : sniffBytes)
                .expand((chunk) => chunk)
                .toList()
          : const <int>[];
      final blocker = fileEditBlocker(
        isWorkingTree: target.isWorkingTree,
        exists: exists,
        binary: looksBinary(head),
        sizeBytes: size,
      );
      if (blocker != null) return EditableFile(blocker: blocker);
      // Malformed bytes are kept rather than rejected: the file is text enough
      // to edit, and refusing to open it would be the more surprising outcome.
      return EditableFile(
        text: utf8.decode(await file.readAsBytes(), allowMalformed: true),
        loadedAt: await file.lastModified(),
      );
    });
