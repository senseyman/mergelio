import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/file_edit.dart';
import '../../domain/git/blob.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/binary_diff.dart';
import '../common/markdown_view.dart';

/// Both versions of a Markdown file rendered: old beside new when [split],
/// otherwise just the new one — or the old one, for a file the change
/// deleted.
class MarkdownCompare extends StatelessWidget {
  final String repoPath;
  final BinarySides sides;

  /// Ties sides that can change under the app to the diff they belong to.
  final Object? version;
  final bool split;

  /// Repo-relative path of each version, for links and images inside it.
  final String beforePath;
  final String afterPath;

  const MarkdownCompare({
    super.key,
    required this.repoPath,
    required this.sides,
    required this.split,
    required this.beforePath,
    required this.afterPath,
    this.version,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    if (!split) {
      final after = sides.after;
      return after != null
          ? _side(after, afterPath)
          : _side(sides.before, beforePath);
    }
    Widget column(String label, BlobRef? side, String path) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: _side(side, path)),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: column(l.bdBefore, sides.before, beforePath)),
        VerticalDivider(width: 1, color: t.border),
        Expanded(child: column(l.bdAfter, sides.after, afterPath)),
      ],
    );
  }

  Widget _side(BlobRef? side, String path) => _MarkdownSide(
    request: side == null
        ? null
        : BlobRequest(repoPath: repoPath, ref: side, version: version),
    path: path,
    // Only the working-tree copy is what sits on disk; images of any other
    // version would show the wrong picture.
    imageRoot: side is WorktreeBlob ? repoPath : null,
  );
}

class _MarkdownSide extends ConsumerWidget {
  final BlobRequest? request;
  final String path;
  final String? imageRoot;
  const _MarkdownSide({
    required this.request,
    required this.path,
    required this.imageRoot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    Widget note(String text) => Center(
      child: Text(text, style: TextStyle(color: t.textFaint, fontSize: 12)),
    );
    final req = request;
    if (req == null) return note(l.mdSideAbsent);
    return ref
        .watch(blobProvider(req))
        .when(
          loading: () => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => note(l.diffCouldNotLoad),
          data: (load) {
            if (load == null) return note(l.mdSideAbsent);
            final bytes = load.bytes;
            // The parser runs on the UI thread on every rebuild; past what the
            // editor would open, a version is not rendered either.
            if (bytes == null || bytes.length > maxEditableBytes) {
              return note(l.bdTooLarge);
            }
            return MarkdownView(
              text: utf8.decode(bytes, allowMalformed: true),
              path: path,
              imageRoot: imageRoot,
            );
          },
        );
  }
}
