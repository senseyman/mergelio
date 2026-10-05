import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_service.dart';
import '../../domain/git/signature.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_data.dart';
import '../../state/signatures.dart';
import '../common/dialogs.dart';
import '../common/signature_badge.dart';

/// Opens the signature check for [repoPath], starting from the current
/// branch's upstream when it has one.
Future<void> showSignatureAudit(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) {
  final branches = ref.read(repoDataProvider(repoPath)).valueOrNull?.branches;
  final upstream =
      branches?.where((b) => b.current).firstOrNull?.upstream ?? '';
  return showAppModal<void>(
    context: context,
    title: AppLocalizations.of(context).sigAuditTitle,
    icon: Icons.verified_user_outlined,
    width: 640,
    body: SignatureAuditPanel(repoPath: repoPath, initialBase: upstream),
  );
}

/// Every commit since a base ref that lacks a verified signature. Checking
/// runs gpg or ssh-keygen per signed commit, so it starts only for a base the
/// user sees in the field.
class SignatureAuditPanel extends ConsumerStatefulWidget {
  final String repoPath;

  /// Base checked on open; empty waits for the user to enter one.
  final String initialBase;
  const SignatureAuditPanel({
    super.key,
    required this.repoPath,
    required this.initialBase,
  });

  @override
  ConsumerState<SignatureAuditPanel> createState() =>
      _SignatureAuditPanelState();
}

class _SignatureAuditPanelState extends ConsumerState<SignatureAuditPanel> {
  late final _base = TextEditingController(text: widget.initialBase);
  late String? _checked = widget.initialBase.trim().isEmpty
      ? null
      : widget.initialBase.trim();

  @override
  void dispose() {
    _base.dispose();
    super.dispose();
  }

  void _run() {
    final base = _base.text.trim();
    if (base.isEmpty) return;
    // Same base again re-verifies: keys or allowed signers may have changed.
    if (base == _checked) {
      ref.invalidate(
        signatureAuditProvider((repo: widget.repoPath, base: base)),
      );
    }
    setState(() => _checked = base);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final checked = _checked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _base,
                autocorrect: false,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: l.sigAuditBase,
                  hintText: l.sigAuditBaseHint,
                  isDense: true,
                ),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _run, child: Text(l.sigAuditRun)),
          ],
        ),
        if (checked != null) ...[
          const SizedBox(height: 8),
          Text(
            // Range syntax is git's, so it stays literal inside the sentence.
            l.sigAuditRange('$checked..HEAD'),
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _Result(repoPath: widget.repoPath, base: checked),
        ],
      ],
    );
  }
}

class _Result extends ConsumerWidget {
  final String repoPath;
  final String base;
  const _Result({required this.repoPath, required this.base});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final body = TextStyle(color: t.textPrimary, fontSize: 13);
    return ref
        .watch(signatureAuditProvider((repo: repoPath, base: base)))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.sigAuditFailed, style: body.copyWith(color: t.danger)),
              Text(
                _reason(e),
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ],
          ),
          data: (audit) {
            final summary = audit.checked == 0
                ? l.sigAuditEmpty
                : audit.unverified.isEmpty
                ? l.sigAuditAllVerified(audit.checked)
                : l.sigAuditSummary(audit.checked, audit.unverified.length);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  summary,
                  style: body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: audit.unverified.isEmpty ? null : t.warning,
                  ),
                ),
                if (audit.truncated)
                  Text(
                    l.sigAuditTruncated(audit.checked),
                    style: TextStyle(color: t.textFaint, fontSize: 12),
                  ),
                if (audit.unverified.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in audit.unverified) _CommitRow(commit: c),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
  }
}

/// What git said, when it said anything; otherwise the short reason.
String _reason(Object error) {
  if (error is GitException) {
    final err = error.result?.err ?? '';
    return err.isNotEmpty ? err : error.message;
  }
  return '$error';
}

class _CommitRow extends ConsumerWidget {
  final UnverifiedCommit commit;
  const _CommitRow({required this.commit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return InkWell(
      onTap: () {
        ref.read(selectedCommitProvider.notifier).state = commit.sha;
        Navigator.of(context).maybePop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            Text(
              commit.shortSha,
              style: AppFonts.mns(size: 11.5, color: t.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                commit.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textPrimary, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                commit.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textFaint, fontSize: 12),
              ),
            ),
            const SizedBox(width: 10),
            // Details live on the commit itself, one tap away.
            Flexible(
              child: SignatureBadge(verdict: commit.verdict, details: false),
            ),
          ],
        ),
      ),
    );
  }
}
