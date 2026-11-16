import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/forge_server.dart';
import '../../domain/forge/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/issue_view.dart';
import '../common/markdown_view.dart';
import '../workspace/forge_presentation.dart';

/// One issue read in the centre column: its number, title, state, author,
/// labels and description as it reads on the forge. Read-only — nothing here
/// writes to the forge.
///
/// Everything shown comes from the single-issue read, never from the sidebar
/// list entry, so a stale title cannot sit beside a fresh description.
class IssueView extends ConsumerWidget {
  const IssueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(issueTargetProvider);
    if (target == null) return const SizedBox.shrink();
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final host = ref.watch(forgeHostProvider(target.repoPath)).valueOrNull;
    final detail = ref.watch(issueDetailProvider(target));
    // The installation errors are worded for. Without a resolved host the
    // read fails before reaching any forge, so the public service stands in.
    final ForgeServer server = host?.server ?? kGithubCloud;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          number: target.number,
          onRefresh: detail.isLoading
              ? null
              : () => ref.invalidate(issueDetailProvider(target)),
          onOpen: host == null ? null : () => _open(context, ref, host, target),
          onClose: () => ref.read(issueTargetProvider.notifier).state = null,
        ),
        Expanded(
          child: switch (detail) {
            AsyncData(value: null) => _Note(l.issueViewNoForge),
            AsyncData(value: final d?) => _Body(detail: d),
            AsyncError(:final error) => _Note(
              forgePanelMessage(error, l, server),
            ),
            _ => const ForgeLoadingRow(),
          },
        ),
        Divider(height: 1, color: t.border),
      ],
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ForgeHost host,
    IssueTarget target,
  ) async {
    final l = AppLocalizations.of(context);
    final toast = ref.read(toastProvider.notifier);
    // Built from the locally resolved host and the number, never from a URL
    // the forge sent back.
    final opened = await ref.read(forgeLaunchUrlProvider)(
      issueWebUrl(host, target.number),
    );
    if (!opened) toast.show(l.forgeCouldNotOpenIssue, kind: ToastKind.error);
  }
}

/// Title bar: the number, plus refresh, open in browser and close.
class _Header extends StatelessWidget {
  final int number;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  const _Header({
    required this.number,
    required this.onRefresh,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            '#$number',
            style: TextStyle(
              color: t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            iconSize: 15,
            tooltip: l.forgeRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            iconSize: 15,
            tooltip: l.forgeOpenInBrowser,
            icon: const Icon(Icons.open_in_new),
            onPressed: onOpen,
          ),
          IconButton(
            iconSize: 15,
            tooltip: l.close,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The issue itself: state, title, who opened it and when, labels, then the
/// description.
class _Body extends StatelessWidget {
  final IssueDetail detail;
  const _Body({required this.detail});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final issue = detail.issue;
    final (stateLabel, stateColor) = switch (issue.state) {
      IssueState.open => (l.rvPrStateOpen, t.success),
      IssueState.closed => (l.rvPrStateClosed, t.danger),
    };
    final meta = forgeMetaLine([
      issue.author.shown,
      forgeAgo(l, issue.updatedAt),
      ...issue.labels,
    ]);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: stateColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                stateLabel,
                style: TextStyle(color: stateColor, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                issue.title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              meta,
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
        const SizedBox(height: 12),
        if (detail.body.trim().isEmpty)
          Text(
            l.rvPrNoDescription,
            style: TextStyle(color: t.textMuted, fontSize: 12),
          )
        else
          MarkdownView(
            text: detail.body,
            // A description is not a file in the repository, so relative
            // links and images have nothing to resolve against and stay inert.
            path: '',
            scrollable: false,
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
    ),
  );
}
