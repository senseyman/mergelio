import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../domain/git/stash.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/stash_contents.dart';
import '../common/change_file_row.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';

/// Right panel content while a stash is selected: what it holds, read without
/// applying it. Tracked changes and untracked files are listed apart, each
/// opening its diff in the sheet, and each can be brought back into the
/// working tree on its own.
class StashPanel extends ConsumerWidget {
  final String repoPath;
  final Stash stash;
  const StashPanel({super.key, required this.repoPath, required this.stash});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final contents = ref.watch(
      stashContentsProvider((repoPath: repoPath, sha: stash.sha)),
    );
    RepoActions actions() => ref.read(repoActionsProvider(repoPath));

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: t.textFaint,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );

    List<PopupMenuEntry<void>> applyItem(
      StashContents c,
      CommitFileChange f, {
      bool untracked = false,
    }) => [
      const PopupMenuDivider(),
      PopupMenuItem(
        height: 34,
        onTap: () => actions().applyStashFile(
          stash.sha,
          c,
          path: f.path,
          origPath: f.origPath,
          untracked: untracked,
        ),
        child: Text(l.stApplyFile, style: const TextStyle(fontSize: 13)),
      ),
    ];

    return Container(
      color: t.bgPanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Text(
                  l.stTitle,
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
                  tooltip: l.close,
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(selectedCommitProvider.notifier).state = null,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stash.ref,
                            style: AppFonts.mns(size: 11, color: t.textFaint),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stash.message.isEmpty ? stash.ref : stash.message,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 15,
                      tooltip: l.stRename,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          promptStashRename(context, actions(), stash),
                    ),
                  ],
                ),
                if (contents.valueOrNull case final c?) ...[
                  const SizedBox(height: 4),
                  Text(
                    l.stBase(_short(c.baseSha)),
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonal(
                      style: _compact,
                      onPressed: () => actions().stashPop(stash.ref),
                      child: Text(l.sbPop),
                    ),
                    OutlinedButton(
                      style: _compact,
                      onPressed: () => actions().stashApply(stash.ref),
                      child: Text(l.apply),
                    ),
                    OutlinedButton(
                      style: _compact,
                      onPressed: () =>
                          promptStashBranch(context, actions(), stash),
                      child: Text(l.stBranch),
                    ),
                    OutlinedButton(
                      style: _compact.copyWith(
                        foregroundColor: WidgetStatePropertyAll(t.danger),
                      ),
                      onPressed: () =>
                          confirmStashDrop(context, ref, actions(), stash),
                      child: Text(l.sbDrop),
                    ),
                  ],
                ),
                ...contents.when(
                  loading: () => const [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ],
                  error: (e, _) => [
                    const SizedBox(height: 14),
                    Text(
                      l.stCouldNotRead,
                      style: TextStyle(color: t.textMuted, fontSize: 12),
                    ),
                  ],
                  data: (c) => [
                    if (c.files.isEmpty && c.untracked.isEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        l.stNoChanges,
                        style: TextStyle(color: t.textFaint, fontSize: 12),
                      ),
                    ],
                    if (c.files.isNotEmpty) ...[
                      sectionLabel(l.cdChangedFiles),
                      for (final f in c.files)
                        ChangeFileRow(
                          file: f,
                          repoPath: repoPath,
                          extraMenu: (_) => applyItem(c, f),
                          onTap: () =>
                              ref
                                  .read(diffTargetProvider.notifier)
                                  .state = DiffTarget(
                                repoPath: repoPath,
                                path: f.path,
                                origPath: f.origPath,
                                commitSha: stash.sha,
                                baseRev: c.baseSha,
                                fromStash: true,
                              ),
                        ),
                    ],
                    if (c.untracked.isNotEmpty) ...[
                      sectionLabel(l.stUntrackedFiles),
                      for (final p in c.untracked)
                        ChangeFileRow(
                          // Applying it creates the file, so it reads as added.
                          file: CommitFileChange(
                            path: p,
                            change: GitChange.added,
                          ),
                          repoPath: repoPath,
                          extraMenu: (_) => applyItem(
                            c,
                            CommitFileChange(path: p, change: GitChange.added),
                            untracked: true,
                          ),
                          // The untracked snapshot is a root commit, so its
                          // own diff shows each file as wholly new.
                          onTap: () =>
                              ref
                                  .read(diffTargetProvider.notifier)
                                  .state = DiffTarget(
                                repoPath: repoPath,
                                path: p,
                                commitSha: c.untrackedSha,
                              ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

final _compact = ButtonStyle(
  visualDensity: VisualDensity.compact,
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  ),
  minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
);

/// Asks for a new message for [stash] and renames it. The renamed stash moves
/// to the top of the list.
Future<void> promptStashRename(
  BuildContext context,
  RepoActions actions,
  Stash stash,
) async {
  final l = AppLocalizations.of(context);
  final message = await showInputDialog(
    context,
    title: l.stRenameTitle(stash.ref),
    label: l.stRenameLabel,
    initial: stash.message,
    confirmLabel: l.stRename,
  );
  if (message == null || message.trim().isEmpty) return;
  if (message.trim() == stash.message) return;
  await actions.stashRename(stash.ref, message.trim());
}

/// Asks for a branch name and turns [stash] into that branch.
Future<void> promptStashBranch(
  BuildContext context,
  RepoActions actions,
  Stash stash,
) async {
  final l = AppLocalizations.of(context);
  final name = await showInputDialog(
    context,
    title: l.stBranchTitle(stash.ref),
    label: l.stBranchLabel,
    confirmLabel: l.stBranchConfirm,
  );
  if (name == null || name.trim().isEmpty) return;
  await actions.stashBranch(name.trim(), stash.ref);
}

/// Confirms, then drops [stash]. The drop itself offers an undo toast.
Future<void> confirmStashDrop(
  BuildContext context,
  WidgetRef ref,
  RepoActions actions,
  Stash stash,
) async {
  final l = AppLocalizations.of(context);
  final ok = await confirmDestructive(
    ref,
    context,
    title: l.sbDropStashTitle(stash.ref),
    body: l.sbDropStashBody,
    confirmLabel: l.sbDrop,
  );
  if (ok) await actions.stashDrop(stash.ref);
}
