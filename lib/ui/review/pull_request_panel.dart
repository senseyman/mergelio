import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/forge_server.dart';
import '../../domain/forge/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/review.dart';
import '../common/markdown_view.dart';
import '../workspace/forge_presentation.dart';

/// What a review opened from a pull request shows above its commits: the
/// request itself, the CI jobs the forge reports for the commit on screen
/// (the first page of each source, up to a hundred), and the description as
/// it reads on the forge. Read-only — nothing here writes to the forge.
///
/// Each part fails on its own: a forge that cannot be read costs this panel
/// its rows, never the diff below, which comes from local git.
class ReviewPullRequestPanel extends ConsumerWidget {
  final ReviewTarget target;
  final ReviewPullRequest pullRequest;

  const ReviewPullRequestPanel({
    super.key,
    required this.target,
    required this.pullRequest,
  });

  /// The installation errors are worded for. The repository's own when it
  /// is known; otherwise the public service of the request's kind, which is
  /// what a request with no resolved host can only have come from.
  ForgeServer _server(ForgeHost? host) =>
      host?.server ??
      switch (pullRequest.kind) {
        ForgeKind.github => kGithubCloud,
        ForgeKind.gitlab => kGitlabCloud,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final pr = pullRequest;
    final repoPath = target.repoPath;
    final sectionsKey = (
      repoPath: repoPath,
      number: pr.number,
      head: target.head,
    );
    final sections = ref.watch(reviewPullRequestSectionsProvider(sectionsKey));
    void setSections(ReviewPullRequestSections next) =>
        ref
                .read(reviewPullRequestSectionsProvider(sectionsKey).notifier)
                .state =
            next;
    final host = ref.watch(forgeHostProvider(repoPath)).valueOrNull;
    final detail = ref.watch(
      pullRequestDetailProvider((
        repoPath: repoPath,
        number: pr.number,
        head: target.head,
      )),
    );
    final checks = ref.watch(
      pullRequestChecksProvider((repoPath: repoPath, sha: target.head)),
    );
    final server = _server(host);
    // Null data means the repository no longer resolves to a forge at all.
    // Saying there is no description or CI would then be a claim about the
    // request, when nothing about it could be read.
    final offForge = switch (detail) {
      AsyncData(value: null) => true,
      _ => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: detail.when(
            loading: () => const _Spinner(),
            error: (e, _) => _Note(forgePanelMessage(e, l, server)),
            data: (d) => d == null
                ? _Note(l.rvPrNoForge)
                : _Heading(
                    detail: d,
                    label: pr.label,
                    reviewedHead: target.head,
                    reviewedTarget: pr.targetBranch,
                    onOpen: host == null
                        ? null
                        : () => _open(context, ref, host),
                  ),
          ),
        ),
        if (!offForge) ...[
          _Toggle(
            // A count only once CI has answered: zero before then would
            // claim there are no jobs.
            label: switch (checks.valueOrNull) {
              final s? => l.rvPrChecks(s.runs.length),
              null => l.rvPrChecksTitle,
            },
            open: sections.checks,
            onTap: () => setSections((
              checks: !sections.checks,
              description: sections.description,
            )),
          ),
          if (sections.checks)
            ...checks.when(
              loading: () => const [_Spinner()],
              error: (e, _) => [_Note(forgePanelMessage(e, l, server))],
              data: (s) => s == null || s.runs.isEmpty
                  ? [_Note(l.rvPrNoChecks)]
                  : [for (final run in s.runs) _CheckRow(run: run)],
            ),
          _Toggle(
            label: l.rvPrDescription,
            open: sections.description,
            onTap: () => setSections((
              checks: sections.checks,
              description: !sections.description,
            )),
          ),
          if (sections.description)
            switch (detail) {
              AsyncData(:final value?) when value.body.trim().isNotEmpty =>
                MarkdownView(
                  text: value.body,
                  // A description is not a file in the repository, so relative
                  // links and images have nothing to resolve against and stay
                  // inert.
                  path: '',
                  scrollable: false,
                  padding: const EdgeInsets.fromLTRB(28, 2, 14, 8),
                ),
              AsyncData(value: _?) => _Note(l.rvPrNoDescription),
              // A failed or pending read already says so in the heading.
              _ => const SizedBox.shrink(),
            },
        ],
        Divider(height: 1, color: t.border),
      ],
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    ForgeHost host,
  ) async {
    final l = AppLocalizations.of(context);
    final toast = ref.read(toastProvider.notifier);
    // Built from the locally resolved host and the number, never from a URL
    // the forge sent back.
    final opened = await ref.read(forgeLaunchUrlProvider)(
      pullRequestWebUrl(host, pullRequest.number),
    );
    if (!opened) {
      toast.show(
        host.kind == ForgeKind.gitlab
            ? l.forgeCouldNotOpenMr
            : l.forgeCouldNotOpenPr,
        kind: ToastKind.error,
      );
    }
  }
}

class _Heading extends StatelessWidget {
  final PullRequestDetail detail;
  final String label;
  final String reviewedHead;

  /// The branch the review's base was fetched from.
  final String reviewedTarget;
  final VoidCallback? onOpen;

  const _Heading({
    required this.detail,
    required this.label,
    required this.reviewedHead,
    required this.reviewedTarget,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final pr = detail.request;
    final (stateLabel, stateColor) = switch (pr.state) {
      PullRequestState.open => (l.rvPrStateOpen, t.success),
      PullRequestState.draft => (l.rvPrStateDraft, t.textMuted),
      PullRequestState.merged => (l.rvPrStateMerged, t.accent),
      PullRequestState.closed => (l.rvPrStateClosed, t.danger),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(label, style: TextStyle(color: t.textMuted, fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pr.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${pr.author.shown} · ${pr.sourceBranch} → ${pr.targetBranch}',
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
            if (onOpen != null)
              Semantics(
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: onOpen,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new, size: 13, color: t.accent),
                      const SizedBox(width: 4),
                      Text(
                        l.forgeOpenInBrowser,
                        style: TextStyle(color: t.accent, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // The diff, the commits and the CI below all describe the commit
        // fetched when the review opened; a request pushed to since has moved
        // on from it.
        if (pr.headSha != reviewedHead) _Warning(l.rvPrHeadMoved),
        // Retargeted since the sidebar listed it: the diff is read against a
        // branch the request no longer asks to merge into.
        if (pr.targetBranch != reviewedTarget)
          _Warning(l.rvPrRetargeted(pr.targetBranch, reviewedTarget)),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final CheckRun run;
  const _CheckRow({required this.run});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final (icon, color, label) = switch (run.state) {
      CheckState.success => (Icons.check, t.success, l.rvCheckSuccess),
      CheckState.failure => (Icons.close, t.danger, l.rvCheckFailure),
      CheckState.running => (Icons.timelapse, t.textMuted, l.rvCheckRunning),
      CheckState.queued => (Icons.schedule, t.textMuted, l.rvCheckQueued),
      CheckState.cancelled => (Icons.block, t.textMuted, l.rvCheckCancelled),
      CheckState.skipped => (Icons.redo, t.textFaint, l.rvCheckSkipped),
      CheckState.unknown => (Icons.help_outline, t.textFaint, l.rvCheckUnknown),
    };
    // One node per job, read as name and outcome: the icon carries the
    // outcome only for someone who can see it.
    return Semantics(
      container: true,
      label: '${run.name}, $label',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 3),
        child: Row(
          children: [
            Tooltip(
              message: label,
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                run.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: 12),
              ),
            ),
            if (run.detailsHint.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  run.detailsHint,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;
  const _Toggle({required this.label, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Merged rather than replaced, so the ink well's own focus and tap stay
    // on the one node the label and state are announced from.
    return MergeSemantics(
      child: Semantics(
        button: true,
        toggled: open,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 4),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: t.textFaint,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  const _Warning(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.warning, fontSize: 12),
    ),
  );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
    child: Text(
      text,
      style: TextStyle(color: context.tokens.textMuted, fontSize: 12),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(8),
    child: Center(
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
