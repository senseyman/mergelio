import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/ignore.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/repo_actions.dart';
import '../common/dialogs.dart';

/// What the user picked in [showIgnoreDialog].
typedef IgnoreChoice = ({IgnoreScope scope, IgnoreTarget target});

/// The working-tree context menu entry that ignores [file]. Empty for
/// anything but an untracked file whose path one ignore line can hold.
List<PopupMenuEntry<void>> ignoreMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required String repoPath,
  required WorkingFile file,
}) {
  if (file.worktree != GitChange.untracked || file.submodule) return const [];
  if (ignoreRule(file.path, IgnoreScope.file) == null) return const [];
  final l = AppLocalizations.of(context);
  // Taken now: the row may be gone by the time the dialog closes.
  final actions = ref.read(repoActionsProvider(repoPath));
  return [
    PopupMenuItem(
      height: 34,
      onTap: () async {
        final nearest = await actions.nearestIgnoreDir(file.path);
        if (!context.mounted) return;
        final choice = await showIgnoreDialog(
          context,
          path: file.path,
          nearestDir: nearest,
        );
        if (choice != null) {
          await actions.addIgnoreRule(file.path, choice.scope, choice.target);
        }
      },
      child: Text(l.wtpIgnore, style: const TextStyle(fontSize: 13)),
    ),
  ];
}

/// Asks how widely to ignore the untracked file at [path] and which ignore
/// file to write. [nearestDir] is the closest nested `.gitignore` directory,
/// offered as a target when set. Null when cancelled.
Future<IgnoreChoice?> showIgnoreDialog(
  BuildContext context, {
  required String path,
  String? nearestDir,
}) => showAppModal<IgnoreChoice>(
  context: context,
  title: AppLocalizations.of(context).ignTitle,
  icon: Icons.visibility_off_outlined,
  width: 520,
  body: _IgnoreBody(path: path, nearestDir: nearestDir),
);

class _IgnoreBody extends StatefulWidget {
  final String path;
  final String? nearestDir;

  const _IgnoreBody({required this.path, this.nearestDir});

  @override
  State<_IgnoreBody> createState() => _IgnoreBodyState();
}

class _IgnoreBodyState extends State<_IgnoreBody> {
  var _scope = IgnoreScope.file;
  var _target = IgnoreTarget.root;

  String get _baseDir =>
      _target == IgnoreTarget.nearest ? widget.nearestDir! : '';

  String? _rule(IgnoreScope s) => ignoreRule(widget.path, s, baseDir: _baseDir);

  void _pickTarget(IgnoreTarget target) => setState(() {
    _target = target;
    // A folder rule can vanish when the base moves down to the file's own
    // directory; the file rule always exists.
    if (_rule(_scope) == null) _scope = IgnoreScope.file;
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final mono = TextStyle(
      fontSize: 12.5,
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      color: t.textMuted,
    );
    const label = TextStyle(fontSize: 13);
    final heading = TextStyle(fontSize: 12, color: t.textFaint);

    Widget tile<T>(
      T value,
      String title,
      String? subtitle, {
      bool code = false,
    }) => RadioListTile<T>(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(title, style: label),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: code ? mono : TextStyle(fontSize: 12, color: t.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
    );

    final ext = p.posix.extension(widget.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.ignWhat, style: heading),
        RadioGroup<IgnoreScope>(
          groupValue: _scope,
          onChanged: (v) => setState(() => _scope = v!),
          child: Column(
            children: [
              for (final s in IgnoreScope.values)
                if (_rule(s) case final rule?)
                  tile(
                    s,
                    switch (s) {
                      IgnoreScope.file => l.ignScopeFile,
                      IgnoreScope.extension => l.ignScopeExtension(ext),
                      IgnoreScope.folder => l.ignScopeFolder,
                    },
                    rule,
                    code: true,
                  ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(l.ignWhere, style: heading),
        RadioGroup<IgnoreTarget>(
          groupValue: _target,
          onChanged: (v) => _pickTarget(v!),
          child: Column(
            children: [
              tile(IgnoreTarget.root, l.ignTargetRoot, null),
              if (widget.nearestDir case final d?)
                tile(
                  IgnoreTarget.nearest,
                  l.ignTargetNearest('$d/.gitignore'),
                  null,
                ),
              tile(
                IgnoreTarget.exclude,
                l.ignTargetExclude,
                l.ignTargetExcludeHint,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop((scope: _scope, target: _target)),
              child: Text(l.ignAdd),
            ),
          ],
        ),
      ],
    );
  }
}
