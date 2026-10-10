import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/patch_file.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../common/dialogs.dart';

/// Larger than any patch a person reviews before applying; reading more
/// would only stall the app.
const _maxPatchBytes = 20 * 1024 * 1024;

/// Picks a patch or `git format-patch` mailbox, dry-runs it against
/// [repoPath] and applies it the way the user chooses. Nothing is committed.
Future<void> showApplyPatchFlow(
  BuildContext context,
  WidgetRef ref,
  String repoPath,
) async {
  final l = AppLocalizations.of(context);
  final toast = ref.read(toastProvider.notifier);
  final actions = ref.read(repoActionsProvider(repoPath));
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: l.apcPickPatch,
        extensions: const ['patch', 'diff', 'mbox', 'eml'],
      ),
      XTypeGroup(label: l.apcAllFiles),
    ],
  );
  if (file == null) return;
  final List<int> bytes;
  try {
    if (await file.length() > _maxPatchBytes) {
      toast.show(l.apcTooLarge, description: file.name, kind: ToastKind.error);
      return;
    }
    bytes = await file.readAsBytes();
  } catch (e) {
    toast.show(l.apcReadFailed, description: '$e', kind: ToastKind.error);
    return;
  }
  final preview = await actions.previewPatch(bytes);
  if (preview == null || !context.mounted) return;
  final mode = await showApplyPatchDialog(
    context,
    fileName: file.name,
    preview: preview,
  );
  if (mode != null) await actions.applyPatchFile(bytes, mode);
}

/// Shows what [preview] would change and asks how to apply it. Null when
/// cancelled.
Future<PatchMode?> showApplyPatchDialog(
  BuildContext context, {
  required String fileName,
  required PatchPreview preview,
}) => showAppModal<PatchMode>(
  context: context,
  title: AppLocalizations.of(context).apcTitle,
  icon: Icons.healing_outlined,
  width: 560,
  body: _ApplyPatchBody(fileName: fileName, preview: preview),
);

class _ApplyPatchBody extends StatefulWidget {
  final String fileName;
  final PatchPreview preview;

  const _ApplyPatchBody({required this.fileName, required this.preview});

  @override
  State<_ApplyPatchBody> createState() => _ApplyPatchBodyState();
}

class _ApplyPatchBodyState extends State<_ApplyPatchBody> {
  late final _modes = widget.preview.modes;
  late PatchMode? _mode = _modes.firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final p = widget.preview;
    final mono = TextStyle(
      fontSize: 12.5,
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      color: t.textPrimary,
    );
    const label = TextStyle(fontSize: 13);
    final heading = TextStyle(fontSize: 12, color: t.textFaint);
    final muted = TextStyle(fontSize: 12, color: t.textMuted);

    Widget tile(PatchMode mode, String title, String subtitle) =>
        RadioListTile<PatchMode>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: mode,
          title: Text(title, style: label),
          subtitle: Text(subtitle, style: muted),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.fileName, style: mono, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          [
            if (p.subjects.isNotEmpty) l.apcMessages(p.subjects.length),
            l.apcFiles(p.files.length),
          ].join(' · '),
          style: muted,
        ),
        if (p.subjects.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 110),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in p.subjects)
                  Text(s, style: label, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(l.apcNoCommitNotice, style: muted.copyWith(color: t.warning)),
        ],
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in p.files)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.path,
                        style: mono.copyWith(color: t.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      f.added == null
                          ? l.apcBinary
                          : '+${f.added} −${f.deleted}',
                      style: muted,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_modes.isEmpty) ...[
          Text(l.apcCannotApply, style: label.copyWith(color: t.danger)),
          if (p.error.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(p.error, style: mono.copyWith(color: t.textMuted)),
          ],
        ] else ...[
          Text(l.apcHow, style: heading),
          RadioGroup<PatchMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v),
            child: Column(
              children: [
                for (final m in _modes)
                  switch (m) {
                    PatchMode.worktree => tile(
                      m,
                      l.apcModeWorktree,
                      l.apcModeWorktreeHint,
                    ),
                    PatchMode.stage => tile(
                      m,
                      l.apcModeStage,
                      l.apcModeStageHint,
                    ),
                    PatchMode.threeWay => tile(
                      m,
                      l.apcModeThreeWay,
                      p.threeWay == ThreeWayCheck.conflicts
                          ? l.apcModeThreeWayConflicts
                          : l.apcModeThreeWayClean,
                    ),
                  },
              ],
            ),
          ),
        ],
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
              onPressed: _mode == null
                  ? null
                  : () => Navigator.of(context).pop(_mode),
              child: Text(l.apcApply),
            ),
          ],
        ),
      ],
    );
  }
}
