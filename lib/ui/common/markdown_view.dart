import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/markdown_links.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';

/// How a web link in a rendered Markdown file opens. Overridable so a test
/// can watch what would have been opened without a real launch reaching a
/// platform channel.
final markdownLaunchUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// A Markdown file shown the way it reads rather than as its source.
class MarkdownView extends ConsumerWidget {
  final String text;

  /// Repo-relative path of the file [text] came from; relative links and
  /// images resolve against it.
  final String path;

  /// Folder on disk a repository image is read from. Null when what is on
  /// disk is not the version being shown, so images show their alt text.
  final String? imageRoot;

  /// Opens another repository file a link points at. Null leaves such links
  /// inert.
  final ValueChanged<String>? onOpenFile;

  const MarkdownView({
    super.key,
    required this.text,
    required this.path,
    this.imageRoot,
    this.onOpenFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          // Line length stays readable on wide windows.
          constraints: const BoxConstraints(maxWidth: 860),
          child: MarkdownBody(
            data: text,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              code: AppFonts.mns(size: 12, color: t.textPrimary),
              codeblockDecoration: BoxDecoration(
                color: t.bgElevated,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onTapLink: (_, href, _) {
              switch (resolveMarkdownHref(href, from: path)) {
                case WebTarget(:final uri):
                  _launch(context, ref, uri);
                case RepoFileTarget(path: final target):
                  onOpenFile?.call(target);
                case null:
                  break;
              }
            },
            imageBuilder: (uri, _, alt) => _image(context, uri, alt),
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, WidgetRef ref, Uri uri) async {
    final failed = AppLocalizations.of(context).mdCouldNotOpenLink;
    final toasts = ref.read(toastProvider.notifier);
    bool opened;
    try {
      opened = await ref.read(markdownLaunchUrlProvider)(uri);
    } on Object {
      opened = false;
    }
    if (!opened) toasts.show(failed, kind: ToastKind.error);
  }

  Widget _image(BuildContext context, Uri uri, String? alt) {
    final target = resolveMarkdownHref(uri.toString(), from: path);
    final root = imageRoot;
    final label = (alt == null || alt.isEmpty) ? '$uri' : alt;
    if (target is RepoFileTarget && root != null) {
      return Image.file(
        File('$root/${target.path}'),
        errorBuilder: (context, _, _) => _ImageStandIn(label: label),
      );
    }
    // Fetching a remote image would tell its host who is reading the file.
    return target is WebTarget
        ? Tooltip(
            message: AppLocalizations.of(context).mdRemoteImageBlocked,
            child: _ImageStandIn(label: label),
          )
        : _ImageStandIn(label: label);
  }
}

/// Stands where an image is not shown.
class _ImageStandIn extends StatelessWidget {
  final String label;
  const _ImageStandIn({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 14, color: t.textFaint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Source | Preview switch for a Markdown file.
class MarkdownViewToggle extends StatelessWidget {
  final bool rendered;
  final ValueChanged<bool> onChanged;
  const MarkdownViewToggle({
    super.key,
    required this.rendered,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    Widget seg(String key, String label, bool on, bool value) => Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey(key),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: on ? t.active : null,
          child: Text(
            label,
            style: TextStyle(
              color: on ? t.textPrimary : t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('md:source', l.mdViewSource, !rendered, false),
          seg('md:rendered', l.mdViewRendered, rendered, true),
        ],
      ),
    );
  }
}
