import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_reader.dart';
import '../../domain/git/review.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_data.dart';
import '../../state/review.dart';
import '../../state/worktrees.dart';
import '../common/dialogs.dart';

/// Asks for a review's two sides. [initial] pre-fills them; without it the
/// checked-out branch is head and a trunk-like branch is base. Both sides are
/// checked to name a commit before the dialog returns, so a typo is caught
/// here rather than surfacing as a failed review.
Future<ReviewTarget?> showReviewPicker(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  ReviewTarget? initial,
}) async {
  // Nothing may have asked for the worktrees yet; wait for them rather than
  // offering a list that silently lacks them. Either read failing only costs
  // suggestions — any revision can still be typed.
  Future<T?> orNull<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  final data = await orNull(ref.read(repoDataProvider(repoPath).future));
  final worktrees = await orNull(ref.read(worktreesProvider(repoPath).future));
  if (!context.mounted) return null;
  final l = AppLocalizations.of(context);
  final choices = reviewRefChoices(
    repoPath: repoPath,
    branches: data?.branches ?? const [],
    remoteBranches: data?.remoteBranches ?? const [],
    tags: data?.tags ?? const [],
    worktrees: worktrees ?? const [],
  );
  final sides = defaultReviewSides(
    data?.branches ?? const [],
    remoteBranches: data?.remoteBranches ?? const [],
  );
  return showAppModal<ReviewTarget>(
    context: context,
    title: l.rvPickTitle,
    icon: Icons.rate_review_outlined,
    width: 480,
    body: _PickerBody(
      repoPath: repoPath,
      choices: choices,
      base: initial?.base ?? sides.base ?? '',
      head: initial?.head ?? sides.head ?? '',
      threeDot: initial?.threeDot ?? true,
    ),
  );
}

class _PickerBody extends ConsumerStatefulWidget {
  final String repoPath;
  final List<RefChoice> choices;
  final String base;
  final String head;
  final bool threeDot;
  const _PickerBody({
    required this.repoPath,
    required this.choices,
    required this.base,
    required this.head,
    required this.threeDot,
  });

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  late final _base = TextEditingController(text: widget.base);
  late final _head = TextEditingController(text: widget.head);
  String? _baseError;
  String? _headError;
  bool _busy = false;

  @override
  void dispose() {
    _base.dispose();
    _head.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final base = _base.text.trim();
    final head = _head.text.trim();
    setState(() => _busy = true);
    final reader = GitReader(ref.read(gitServiceProvider), widget.repoPath);
    Future<String?> check(String rev) async {
      if (rev.isEmpty) return l.rvNotACommit(rev);
      try {
        await reader.resolveCommit(rev);
        return null;
      } catch (_) {
        return l.rvNotACommit(rev);
      }
    }

    final [baseError, headError] = await Future.wait([
      check(base),
      check(head),
    ]);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _baseError = baseError;
      _headError = headError;
    });
    if (baseError != null || headError != null) return;
    Navigator.of(context).pop(
      ReviewTarget(
        repoPath: widget.repoPath,
        base: base,
        head: head,
        threeDot: widget.threeDot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final hasWorktrees = widget.choices.any(
      (c) => c.kind == RefChoiceKind.worktree,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RefField(
          label: l.rvBase,
          controller: _base,
          choices: widget.choices,
          error: _baseError,
          onSubmit: _submit,
        ),
        const SizedBox(height: 12),
        _RefField(
          label: l.rvHead,
          controller: _head,
          choices: widget.choices,
          error: _headError,
          onSubmit: _submit,
        ),
        if (hasWorktrees) ...[
          const SizedBox(height: 10),
          Text(
            l.rvWorktreeNote,
            style: TextStyle(color: t.textFaint, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(l.rvOpen),
            ),
          ],
        ),
      ],
    );
  }
}

/// A revision field that suggests branches, tags and worktrees as the user
/// types, while still taking anything git can resolve — a sha, `HEAD~3`.
class _RefField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final List<RefChoice> choices;
  final String? error;
  final VoidCallback onSubmit;
  const _RefField({
    required this.label,
    required this.controller,
    required this.choices,
    required this.error,
    required this.onSubmit,
  });

  @override
  State<_RefField> createState() => _RefFieldState();
}

class _RefFieldState extends State<_RefField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    String kind(RefChoiceKind k) => switch (k) {
      RefChoiceKind.branch => l.rvKindBranch,
      RefChoiceKind.remote => l.rvKindRemote,
      RefChoiceKind.tag => l.rvKindTag,
      RefChoiceKind.worktree => l.rvKindWorktree,
    };
    return RawAutocomplete<RefChoice>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (c) => c.rev,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return [
          for (final c in widget.choices)
            if (q.isEmpty ||
                c.rev.toLowerCase().contains(q) ||
                (c.detail?.toLowerCase().contains(q) ?? false))
              c,
        ].take(50);
      },
      fieldViewBuilder: (context, ctl, focus, submit) => TextField(
        controller: ctl,
        focusNode: focus,
        autocorrect: false,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: l.rvSideHint,
          errorText: widget.error,
          isDense: true,
        ),
        onSubmitted: (_) => widget.onSubmit(),
      ),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: t.bgElevated,
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 440),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final c in options)
                  InkWell(
                    onTap: () => select(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.rev,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 0,
                            child: Text(
                              c.detail == null
                                  ? kind(c.kind)
                                  : '${kind(c.kind)} · ${c.detail}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textFaint,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
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
