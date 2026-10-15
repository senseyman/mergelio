import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/tokens.dart';
import '../../domain/release_notes/release_notes.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/release_notes.dart';
import '../../state/workspace.dart';

/// How a link in the notes opens. Overridable so a test can watch what would
/// have been opened without a real launch reaching a platform channel.
final releaseNotesLaunchUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => launchUrl,
);

/// Body of the "What's new" tab: each version's notes, newest first.
class ReleaseNotesView extends ConsumerWidget {
  const ReleaseNotesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final versions =
        ref.watch(workspaceProvider.select((w) => w.releaseNotes)) ??
        const <Version>[];
    final assets = ref.watch(releaseNotesAssetsProvider).valueOrNull;
    if (assets == null) return ColoredBox(color: t.bgPanel);
    final lang = Localizations.localeOf(context).languageCode;
    final shown = [
      for (final v in versions)
        if (assets.containsKey(v)) v,
    ];

    return ColoredBox(
      color: t.bgPanel,
      child: shown.isEmpty
          ? Center(
              child: Text(l.rnEmpty, style: TextStyle(color: t.textMuted)),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              children: [
                for (final v in shown)
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      // Line length stays readable on wide windows.
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _VersionNotes(
                        version: v,
                        assetKey: notesAssetFor(v, lang, assets[v]!),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _VersionNotes extends ConsumerWidget {
  final Version version;
  final String assetKey;
  const _VersionNotes({required this.version, required this.assetKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final text = ref.watch(releaseNotesTextProvider(assetKey)).valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.rnVersionHeading(version.toString()),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (text != null)
            MarkdownBody(
              data: text,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              onTapLink: (_, href, _) {
                final uri = href == null ? null : Uri.tryParse(href);
                // Notes are ours, but a link only ever leaves for the web.
                if (uri == null ||
                    !(uri.isScheme('https') || uri.isScheme('http'))) {
                  return;
                }
                ref.read(releaseNotesLaunchUrlProvider)(uri);
              },
            ),
        ],
      ),
    );
  }
}
