import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/commit_message.dart';
import '../../domain/git/models.dart';
import '../../domain/git/signature.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/graph_selection.dart';
import '../../state/lfs.dart';
import '../../state/repo_data.dart';
import '../../state/settings_controller.dart';
import '../../state/signatures.dart';
import '../common/change_file_row.dart';
import '../common/file_tree_view.dart';
import '../common/signature_badge.dart';
import '../graph/commit_columns.dart';
import '../graph/ref_pill.dart';
import 'edit_commit_message.dart';
import 'lfs_lock_menu.dart';

/// Right panel content for a selected commit: metadata, signature, the list of
/// changed files (read-only), and a `‹ WIP` shortcut back to the working tree
/// when it is dirty.
class CommitDetails extends ConsumerWidget {
  final String repoPath;
  final Commit commit;
  final bool hasWip;
  const CommitDetails({
    super.key,
    required this.repoPath,
    required this.commit,
    required this.hasWip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final c = commit;
    final files = ref.watch(commitFilesProvider((repo: repoPath, sha: c.sha)));
    final clock = ref.watch(settingsProvider.select((s) => s.clockFormat));
    // Null while verification is still running, so the row appears once
    // known. An unsigned commit gets no row.
    final sig = ref
        .watch(commitSignatureProvider((repo: repoPath, sha: c.sha)))
        .valueOrNull;
    final tags = [
      for (final r in c.refs)
        if (r.kind == RefKind.tag) r.name,
    ];

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Text(
                  l.cdCommit,
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (hasWip)
                  TextButton(
                    onPressed: () =>
                        ref.read(selectedCommitProvider.notifier).state =
                            wipSelection,
                    child: Text(l.cdWip, style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        c.message,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                    _MsgAction(
                      icon: Icons.edit_outlined,
                      tooltip: l.menuEditMessage,
                      onTap: () => editCommitMessage(
                        context,
                        ref,
                        repoPath: repoPath,
                        commit: c,
                      ),
                    ),
                    _MsgAction(
                      icon: Icons.content_copy_outlined,
                      tooltip: l.menuCopySummary,
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: c.message)),
                    ),
                  ],
                ),
                if (c.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          c.body,
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                      _MsgAction(
                        icon: Icons.content_copy_outlined,
                        tooltip: l.menuCopyDescription,
                        onTap: () =>
                            Clipboard.setData(ClipboardData(text: c.body)),
                      ),
                      _MsgAction(
                        icon: Icons.copy_all_outlined,
                        tooltip: l.menuCopyMessage,
                        onTap: () => Clipboard.setData(
                          ClipboardData(
                            text: joinCommitMessage(c.message, c.body),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (c.refs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final r in c.refs)
                        RefPill(gitRef: r, ellipsize: true),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _Meta(
                  label: l.cdAuthor,
                  value: '${c.author} <${c.authorEmail}>',
                ),
                _Meta(
                  label: l.cdDate,
                  value: formatCommitDate(
                    c.date,
                    withTime: true,
                    clock: clock,
                    offset: c.dateOffset,
                  ),
                ),
                _MetaSha(sha: c.sha),
                for (final p in c.parents)
                  _Meta(
                    label: l.cdParent,
                    value: p.length > 7 ? p.substring(0, 7) : p,
                    mono: true,
                  ),
                if (sig != null && sig.isSigned)
                  _Signature(repoPath: repoPath, verdict: sig),
                if (tags.isNotEmpty)
                  _TagSignatures(
                    // A fresh list per commit, so one commit's "show all"
                    // does not carry over to the next.
                    key: ValueKey(c.sha),
                    repoPath: repoPath,
                    tags: tags,
                  ),
                if (c.coauthor)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.group_outlined, size: 13, color: t.accent),
                        const SizedBox(width: 6),
                        Text(
                          l.cdCoauthored,
                          style: TextStyle(color: t.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l.cdChangedFiles,
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    const FileViewToggle(),
                  ],
                ),
                const SizedBox(height: 6),
                files.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    l.cdCouldNotRead,
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Text(
                        l.cdNoChanges,
                        style: TextStyle(color: t.textFaint, fontSize: 12),
                      );
                    }
                    final tree = ref.watch(
                      settingsProvider.select((s) => s.filesAsTree),
                    );
                    final byPath = {for (final f in list) f.path: f};
                    final lfs =
                        ref
                            .watch(
                              lfsPathsProvider(
                                LfsQuery(
                                  LfsSource(
                                    repoPath: repoPath,
                                    rev: c.sha,
                                    parentRev: c.parents.isEmpty
                                        ? null
                                        : c.parents.first,
                                  ),
                                  [for (final f in list) f.path],
                                ),
                              ),
                            )
                            .valueOrNull ??
                        const <String>{};
                    final locks =
                        ref.watch(lfsLocksProvider(repoPath)).valueOrNull ??
                        LfsLockState.none;
                    return FileTreeView(
                      paths: [for (final f in list) f.path],
                      tree: tree,
                      fileRow: (path, depth) => ChangeFileRow(
                        file: byPath[path]!,
                        repoPath: repoPath,
                        indent: FileTreeView.indent(depth),
                        inTree: tree,
                        lfs: lfs.contains(path),
                        lock: locks.lockFor(path),
                        lockIsOurs: locks.isOurs(path),
                        extraMenu: (ctx) => lfsLockMenuItems(
                          context: ctx,
                          ref: ref,
                          repoPath: repoPath,
                          path: path,
                          isLfs: lfs.contains(path),
                        ),
                        onTap: () =>
                            ref
                                .read(diffTargetProvider.notifier)
                                .state = DiffTarget(
                              repoPath: repoPath,
                              path: path,
                              commitSha: c.sha,
                              origPath: byPath[path]!.origPath,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small icon affordance sitting beside the message it acts on, sized to the
/// text rather than to a stock [IconButton]'s tap target so it does not push
/// the message it belongs to out of the way.
class _MsgAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MsgAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 13, color: t.textFaint),
        ),
      ),
    );
  }
}

/// Tags verified on their own before the user asks for more. Each one costs a
/// `git verify-tag` and a gpg or ssh-keygen process, and a commit can carry
/// dozens of tags in a repository that tags every package's release.
const kMaxVerifiedTags = 5;

/// Signature rows for a commit's tags: the first [kMaxVerifiedTags] verified
/// straight away, the rest behind one action.
class _TagSignatures extends StatefulWidget {
  final String repoPath;
  final List<String> tags;
  const _TagSignatures({super.key, required this.repoPath, required this.tags});

  @override
  State<_TagSignatures> createState() => _TagSignaturesState();
}

class _TagSignaturesState extends State<_TagSignatures> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final tags = widget.tags;
    final shown = _all ? tags : tags.take(kMaxVerifiedTags).toList();
    final rest = tags.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tag in shown)
          _TagSignature(repoPath: widget.repoPath, tag: tag),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _all = true),
              child: Text(
                l.sigMoreTags(rest),
                style: TextStyle(color: t.accent, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

/// A tag's signature row, verified on demand. Nothing while it is checked,
/// nor for a lightweight or unsigned tag.
class _TagSignature extends ConsumerWidget {
  final String repoPath;
  final String tag;
  const _TagSignature({required this.repoPath, required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verdict = ref
        .watch(tagSignatureProvider((repo: repoPath, name: tag)))
        .valueOrNull;
    if (verdict == null || !verdict.isSigned) return const SizedBox.shrink();
    return _Signature(repoPath: repoPath, verdict: verdict, tag: tag);
  }
}

/// One signature row: the commit's own, or a signed tag's when [tag] names
/// it. The allowed signers file is read only for an SSH signature git could
/// not attribute, and only when the verifier's output does not already name
/// the file it failed to open.
class _Signature extends ConsumerWidget {
  final String repoPath;
  final SignatureVerdict verdict;
  final String? tag;
  const _Signature({required this.repoPath, required this.verdict, this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final needsSigners =
        verdict.isSsh &&
        verdict.state == SignatureState.untrusted &&
        allowedSignersPathIn(verdict.detail) == null;
    final signers = needsSigners
        ? ref.watch(allowedSignersFileProvider(repoPath)).valueOrNull
        : null;
    final badge = SignatureBadge(verdict: verdict, allowedSignersFile: signers);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: tag == null
          ? badge
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    l.sigTag(tag!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textFaint, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: badge),
              ],
            ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _Meta({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? AppFonts.mns(size: 11.5, color: t.textMuted)
                  : TextStyle(color: t.textMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaSha extends StatelessWidget {
  final String sha;
  const _MetaSha({required this.sha});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final short = sha.length > 7 ? sha.substring(0, 7) : sha;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              l.cdSha,
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
          Text(short, style: AppFonts.mns(size: 11.5, color: t.textMuted)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: sha)),
            child: Icon(Icons.copy_outlined, size: 12, color: t.textFaint),
          ),
        ],
      ),
    );
  }
}
