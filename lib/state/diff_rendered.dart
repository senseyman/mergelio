import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/markdown_links.dart';
import 'diff_document.dart';
import 'file_editor.dart';

/// Markdown files the diff sheet shows rendered rather than as a diff. Each
/// file opens on its diff and keeps the choice for the rest of the session.
final diffRenderedFilesProvider =
    StateNotifierProvider<DiffRenderedFiles, Set<FileRef>>(
      (_) => DiffRenderedFiles(),
    );

class DiffRenderedFiles extends StateNotifier<Set<FileRef>> {
  DiffRenderedFiles() : super(const {});

  void set(FileRef file, bool rendered) {
    if (state.contains(file) == rendered) return;
    state = rendered ? {...state, file} : ({...state}..remove(file));
  }
}

/// Whether [doc], the diff of the file at [path], has text worth rendering.
/// An LFS file shows its card or its pointer, a binary one its bytes, and an
/// empty diff has nothing to show — the header and the body both go by this,
/// so the switch is never offered for a view that would not appear.
bool canRenderMarkdownDiff(String path, DiffDoc doc) =>
    isMarkdownPath(path) &&
    !doc.isEmpty &&
    !doc.isBinary &&
    !doc.files.any((f) => f.lfs != null);
