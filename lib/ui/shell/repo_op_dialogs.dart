import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/dialogs.dart';
import 'remote_merge_confirm.dart';
import '../../l10n/gen/app_localizations.dart';

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
                      await actions.merge(source);
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
