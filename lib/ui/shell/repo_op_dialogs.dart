import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_writer.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/dialogs.dart';
import 'remote_merge_confirm.dart';

/// Create-branch dialog: name, the branch to start from (defaults to the
/// current one) and a checkout-after toggle.
Future<void> showBranchDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  final branches =
      ref.read(repoDataProvider(repoPath)).valueOrNull?.branches ??
      const <Branch>[];
  final current = branches.where((b) => b.current).firstOrNull?.name;
  await showAppModal<void>(
    context: context,
    title: l.ropCreateBranchTitle,
    icon: Icons.call_split,
    body: _BranchBody(
      repoPath: repoPath,
      branches: [for (final b in branches) b.name],
      initialFrom: current,
    ),
  );
}

/// Merge dialog: pick a branch to merge into the current one. Remote-tracking
/// branches are offered too, listed after the local ones.
Future<void> showMergeDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  // Awaited rather than read: a snapshot taken before the repository has
  // loaded would offer an empty branch list.
  RepoData? data;
  try {
    data = await ref.read(repoDataProvider(repoPath).future);
  } on Object catch (_) {
    data = null;
  }
  if (!context.mounted) return;
  final branches = data?.branches ?? const <Branch>[];
  final current = branches.where((b) => b.current).firstOrNull?.name;
  final others = [
    for (final b in branches)
      if (!b.current) b.name,
  ];
  final remotes = [
    for (final rb in data?.remoteBranches ?? const <RemoteBranch>[]) rb.name,
  ];
  await showAppModal<void>(
    context: context,
    title: l.ropMergeIntoTitle(current ?? l.ropCurrentBranch),
    icon: Icons.merge,
    body: _MergeBody(
      repoPath: repoPath,
      branches: others,
      remoteBranches: remotes,
    ),
  );
}

/// Create-tag dialog: name, lightweight/annotated choice, and a message for
/// annotated tags. [at] pins the tag to a specific commit.
Future<void> showTagDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath, {
  String? at,
}) => showAppModal<void>(
  context: context,
  title: AppLocalizations.of(context).ropCreateTagTitle,
  icon: Icons.sell_outlined,
  body: _TagBody(repoPath: repoPath, at: at),
);

class _TagBody extends ConsumerStatefulWidget {
  final String repoPath;
  final String? at;
  const _TagBody({required this.repoPath, required this.at});

  @override
  ConsumerState<_TagBody> createState() => _TagBodyState();
}

class _TagBodyState extends ConsumerState<_TagBody> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  bool _annotated = false;

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.ropTagName, style: TextStyle(color: t.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'v1.0.0',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                l.ropType,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            for (final (label, annotated) in const [
              ('lightweight', false),
              ('annotated', true),
            ])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _annotated == annotated,
                  onSelected: (_) => setState(() => _annotated = annotated),
                ),
              ),
          ],
        ),
        if (_annotated) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: l.ropTagMessage,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.rButton),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () {
                      // Capture before pop — the route's dispose owns the
                      // controllers.
                      final actions = ref.read(
                        repoActionsProvider(widget.repoPath),
                      );
                      final name = _name.text.trim();
                      final msg = _message.text.trim();
                      final annotated = _annotated;
                      Navigator.of(context).pop();
                      actions.createTag(
                        name,
                        at: widget.at,
                        message: annotated ? (msg.isEmpty ? name : msg) : null,
                      );
                    },
              child: Text(l.create),
            ),
          ],
        ),
      ],
    );
  }
}

/// Stash dialog: optional message + "only staged changes" toggle.
Future<void> showStashDialog(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) => showAppModal<void>(
  context: context,
  title: AppLocalizations.of(context).ropStashChangesTitle,
  icon: Icons.inventory_2_outlined,
  body: _StashBody(repoPath: repoPath),
);

class _BranchBody extends ConsumerStatefulWidget {
  final String repoPath;
  final List<String> branches;
  final String? initialFrom;
  const _BranchBody({
    required this.repoPath,
    required this.branches,
    required this.initialFrom,
  });

  @override
  ConsumerState<_BranchBody> createState() => _BranchBodyState();
}

class _BranchBodyState extends ConsumerState<_BranchBody> {
  final _name = TextEditingController();
  late String? _from = widget.initialFrom;
  bool _checkout = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    // Capture everything before pop: the route's dispose runs before the
    // awaits resume, so touching controllers afterwards would throw.
    final actions = ref.read(repoActionsProvider(widget.repoPath));
    final name = _name.text.trim();
    final from = _from;
    final checkout = _checkout;
    Navigator.of(context).pop();
    await actions.createBranch(name, at: from);
    if (checkout) await actions.checkout(name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.ropBranchName,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'feature/…',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l.ropStartFrom,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _from,
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
          items: [
            for (final b in widget.branches)
              DropdownMenuItem(
                value: b,
                child: Text(b, style: const TextStyle(fontSize: 13)),
              ),
          ],
          onChanged: (v) => setState(() => _from = v),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.ropCheckoutAfterCreating,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: _checkout,
          onChanged: (v) => setState(() => _checkout = v ?? true),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _name.text.trim().isEmpty ? null : _create,
              child: Text(l.create),
            ),
          ],
        ),
      ],
    );
  }
}

class _MergeBody extends ConsumerStatefulWidget {
  final String repoPath;
  final List<String> branches;
  final List<String> remoteBranches;
  const _MergeBody({
    required this.repoPath,
    required this.branches,
    this.remoteBranches = const [],
  });

  @override
  ConsumerState<_MergeBody> createState() => _MergeBodyState();
}

class _MergeBodyState extends ConsumerState<_MergeBody> {
  bool _squash = false;
  bool _noCommit = false;
  MergeFavor _favor = MergeFavor.none;
  String? _branch;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    if (widget.branches.isEmpty && widget.remoteBranches.isEmpty) {
      return Text(
        l.ropNoOtherBranches,
        style: TextStyle(color: t.textMuted, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.ropBranchToMerge,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
          items: [
            for (final b in widget.branches)
              DropdownMenuItem(
                value: b,
                child: Text(b, style: const TextStyle(fontSize: 13)),
              ),
            // Remote-tracking refs merge exactly like local branches; the
            // cloud icon keeps them tellable apart in the closed field too.
            for (final b in widget.remoteBranches)
              DropdownMenuItem(
                value: b,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_outlined, size: 13, color: t.textFaint),
                    const SizedBox(width: 6),
                    Text(b, style: TextStyle(fontSize: 13, color: t.textMuted)),
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _branch = v),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.ropSquash,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: _squash,
          // A squash never commits, so it subsumes the choice below rather
          // than leaving a checked-but-ignored box behind.
          onChanged: (v) => setState(() {
            _squash = v ?? false;
            if (_squash) _noCommit = false;
          }),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.ropNoCommit,
            style: TextStyle(
              color: _squash ? t.textFaint : t.textPrimary,
              fontSize: 13,
            ),
          ),
          value: _noCommit,
          onChanged: _squash
              ? null
              : (v) => setState(() => _noCommit = v ?? false),
        ),
        const SizedBox(height: 6),
        Text(
          l.ropFavorLabel,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<MergeFavor>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: [
              ButtonSegment(value: MergeFavor.none, label: Text(l.ropFavorAsk)),
              ButtonSegment(
                value: MergeFavor.ours,
                label: Text(l.ropFavorOurs),
              ),
              ButtonSegment(
                value: MergeFavor.theirs,
                label: Text(l.ropFavorTheirs),
              ),
            ],
            selected: {_favor},
            onSelectionChanged: (v) => setState(() => _favor = v.first),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _branch == null
                  ? null
                  : () async {
                      final source = _branch!;
                      final actions = ref.read(
                        repoActionsProvider(widget.repoPath),
                      );
                      final navigator = Navigator.of(context);
                      // Backing out of the fetch question returns to the
                      // picker; only a real merge closes the dialog.
                      if (!await confirmRemoteSource(
                        context,
                        ref,
                        repoPath: widget.repoPath,
                        source: source,
                      )) {
                        return;
                      }
                      navigator.pop();
                      await actions.merge(
                        source,
                        squash: _squash,
                        noCommit: _noCommit,
                        favor: _favor,
                      );
                    },
              child: Text(l.ropMerge),
            ),
          ],
        ),
      ],
    );
  }
}

class _StashBody extends ConsumerStatefulWidget {
  final String repoPath;
  const _StashBody({required this.repoPath});

  @override
  ConsumerState<_StashBody> createState() => _StashBodyState();
}

class _StashBodyState extends ConsumerState<_StashBody> {
  final _message = TextEditingController();
  bool _stagedOnly = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.ropMessageOptional,
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _message,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'wip: …',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(t.rButton),
            ),
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            l.ropOnlyStaged,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          value: _stagedOnly,
          onChanged: (v) => setState(() => _stagedOnly = v ?? false),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final actions = ref.read(repoActionsProvider(widget.repoPath));
                final msg = _message.text.trim();
                Navigator.of(context).pop();
                actions.stashPush(
                  message: msg.isEmpty ? null : msg,
                  stagedOnly: _stagedOnly,
                );
              },
              child: Text(l.ropStash),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cherry-picks or reverts [commit], asking [pick] for the mainline parent
/// first when it is a merge. A null from [pick] is a cancellation: nothing
/// runs. Split from the menu that calls it so the branching is testable
/// without a graph on screen.
Future<void> replayCommit({
  required Commit commit,
  required MainlineOp op,
  required RepoActions actions,
  required Future<int?> Function() pick,
}) async {
  int? mainline;
  if (needsMainline(commit)) {
    mainline = await pick();
    if (mainline == null) return;
  }
  switch (op) {
    case MainlineOp.cherryPick:
      await actions.cherryPick(commit.sha, mainline: mainline);
    case MainlineOp.revert:
      await actions.revert(commit.sha, mainline: mainline);
  }
}

/// Whether git will refuse to replay [commit] without being told which parent
/// to treat as the mainline — true for merge commits only.
bool needsMainline(Commit commit) => commit.parents.length > 1;

/// Subjects of [commit]'s parents, taken from the already-loaded [commits].
/// A parent outside the loaded walk is simply absent, and shows as a sha.
Map<String, String> parentSubjects(Commit commit, List<Commit> commits) {
  final wanted = commit.parents.toSet();
  return {
    for (final c in commits)
      if (wanted.contains(c.sha)) c.sha: c.message,
  };
}

/// The two commands git refuses to run on a merge commit without `-m`.
enum MainlineOp { cherryPick, revert }

/// Asks which parent of a merge commit git should work against. Returns the
/// 1-based parent number, or null when the user backs out. [subjects] maps a
/// parent sha to its commit subject, so the choice reads as branches rather
/// than hashes; a parent that is missing from it just shows its sha.
Future<int?> showMainlineDialog(
  BuildContext context, {
  required Commit commit,
  required MainlineOp op,
  Map<String, String> subjects = const {},
}) {
  final l = AppLocalizations.of(context);
  return showAppModal<int>(
    context: context,
    title: op == MainlineOp.revert
        ? l.ropMainlineRevertTitle(commit.shortSha)
        : l.ropMainlineCherryPickTitle(commit.shortSha),
    icon: Icons.merge_type,
    width: 480,
    body: _MainlineBody(commit: commit, op: op, subjects: subjects),
  );
}

class _MainlineBody extends StatefulWidget {
  final Commit commit;
  final MainlineOp op;
  final Map<String, String> subjects;
  const _MainlineBody({
    required this.commit,
    required this.op,
    required this.subjects,
  });

  @override
  State<_MainlineBody> createState() => _MainlineBodyState();
}

class _MainlineBodyState extends State<_MainlineBody> {
  // 1-based, like git's -m: parent 1 is the branch the merge landed on, which
  // is what people mean nearly every time.
  int _parent = 1;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final parents = widget.commit.parents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.op == MainlineOp.revert
              ? l.ropMainlineRevertBody
              : l.ropMainlineCherryPickBody,
          style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < parents.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ParentTile(
              number: i + 1,
              sha: parents[i],
              subject: widget.subjects[parents[i]],
              selected: _parent == i + 1,
              onTap: () => setState(() => _parent = i + 1),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_parent),
              child: Text(
                widget.op == MainlineOp.revert
                    ? l.menuRevert
                    : l.menuCherryPick,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ParentTile extends StatelessWidget {
  final int number;
  final String sha;
  final String? subject;
  final bool selected;
  final VoidCallback onTap;
  const _ParentTile({
    required this.number,
    required this.sha,
    required this.subject,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final role = number == 1
        ? l.ropMainlineParentFirst
        : l.ropMainlineParentOther;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.rButton),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.rButton),
            border: Border.all(color: selected ? t.accent : t.border),
            color: selected ? t.accent.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? t.accent : t.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${l.ropMainlineParent(number)} · $role',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          sha.length > 7 ? sha.substring(0, 7) : sha,
                          style: AppFonts.mns(size: 11.5, color: t.textMuted),
                        ),
                      ],
                    ),
                    if (subject != null && subject!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subject!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textMuted, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
