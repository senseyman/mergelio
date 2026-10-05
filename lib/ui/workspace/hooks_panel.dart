import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/hooks.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/hooks.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import '../common/file_text_editor.dart';

Future<void> showHooksPanel(BuildContext context, String repoPath) =>
    showAppModal<void>(
      context: context,
      title: AppLocalizations.of(context).hkTitle,
      icon: Icons.webhook_outlined,
      width: 640,
      body: HooksPanel(repoPath: repoPath),
    );

/// The hooks git runs for a repository: where they live, which are on, and
/// the tool that manages them when there is one.
class HooksPanel extends ConsumerWidget {
  final String repoPath;
  const HooksPanel({super.key, required this.repoPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(hookInventoryProvider(repoPath))
        .when(
          loading: () => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (e, _) =>
              Text('$e', style: TextStyle(color: t.danger, fontSize: 12)),
          data: (inv) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.hkDir, style: TextStyle(color: t.textFaint, fontSize: 11)),
              const SizedBox(height: 2),
              SelectableText(
                inv.dir,
                style: AppFonts.mns(size: 12, color: t.textPrimary),
              ),
              if (inv.customPath != null) ...[
                const SizedBox(height: 4),
                Text(
                  l.hkCustomPath(inv.customPath!),
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                ),
              ],
              if (inv.manager != null) ...[
                const SizedBox(height: 10),
                _ManagerBanner(manager: inv.manager!),
              ],
              const SizedBox(height: 14),
              if (inv.hooks.isEmpty)
                Text(
                  l.hkEmpty,
                  style: TextStyle(color: t.textMuted, fontSize: 12.5),
                )
              else
                for (final h in inv.hooks)
                  _HookRow(repoPath: repoPath, dir: inv.dir, hook: h),
            ],
          ),
        );
  }
}

/// Waits for a hook change and, when it was refused, says why. Reports
/// whether it landed.
Future<bool> reportHookWrite(
  WidgetRef ref,
  AppLocalizations l,
  String hook,
  Future<HookWriteException?> write,
) async {
  final failure = await write;
  if (failure == null) return true;
  ref
      .read(toastProvider.notifier)
      .show(
        l.hkChangeFailed(hook),
        description: switch (failure.failure) {
          HookWriteFailure.notFound => l.hkFailNotFound,
          HookWriteFailure.alreadyExists => l.hkFailExists,
          HookWriteFailure.outsideRepository => l.hkFailOutside,
          HookWriteFailure.linked => l.hkFailLinked,
          HookWriteFailure.io => failure.detail,
        },
        kind: ToastKind.error,
      );
  return false;
}

String _managerName(HookManager m) => switch (m) {
  HookManager.husky => 'husky',
  HookManager.lefthook => 'lefthook',
  HookManager.preCommit => 'pre-commit',
};

class _ManagerBanner extends StatelessWidget {
  final HookManager manager;
  const _ManagerBanner({required this.manager});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: t.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).hkManaged(_managerName(manager)),
              style: TextStyle(color: t.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _HookRow extends ConsumerWidget {
  final String repoPath;
  final String dir;
  final HookFile hook;
  const _HookRow({
    required this.repoPath,
    required this.dir,
    required this.hook,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final actions = ref.read(hookActionsProvider(repoPath));
    final (label, color) = switch (hook.state) {
      HookState.active => (l.hkStateActive, t.success),
      HookState.disabled => (l.hkStateDisabled, t.textMuted),
      HookState.sample => (l.hkStateSample, t.textFaint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hook.name,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.mns(
                size: 12.5,
                color: hook.installed ? t.textPrimary : t.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Text(label, style: TextStyle(color: color, fontSize: 11)),
          ),
          const SizedBox(width: 4),
          if (hook.installed) ...[
            // Windows runs every hook regardless of its mode, so there is
            // nothing for a switch to change there.
            if (defaultTargetPlatform != TargetPlatform.windows)
              Tooltip(
                message: hook.isLink
                    ? l.hkLinkedNoToggle
                    : hook.state == HookState.active
                    ? l.hkDisable
                    : l.hkEnable,
                child: Switch(
                  key: ValueKey('hook:switch:${hook.name}'),
                  value: hook.state == HookState.active,
                  onChanged: hook.isLink
                      ? null
                      : (on) => reportHookWrite(
                          ref,
                          l,
                          hook.name,
                          actions.setEnabled(dir, hook.name, enabled: on),
                        ),
                ),
              ),
            TextButton(
              onPressed: () => _showHookEditor(context, repoPath, dir, hook),
              child: Text(l.hkEdit),
            ),
          ] else
            TextButton(
              onPressed: () => reportHookWrite(
                ref,
                l,
                hook.name,
                actions.useSample(dir, hook.name),
              ),
              child: Text(l.hkUseSample),
            ),
        ],
      ),
    );
  }
}

/// Opens a hook in the shared editor, rooted at the hooks directory so the
/// editor's read and its external-change check both see the hook file itself.
/// Saving goes through the hook writer, which keeps the write inside the
/// hooks directory or the repository.
Future<void> _showHookEditor(
  BuildContext context,
  String repoPath,
  String dir,
  HookFile hook,
) => showAppModal<void>(
  context: context,
  title: AppLocalizations.of(context).hkEditorTitle(hook.name),
  icon: Icons.webhook_outlined,
  width: 760,
  body: _HookEditor(repoPath: repoPath, dir: dir, name: hook.name),
);

class _HookEditor extends ConsumerStatefulWidget {
  final String repoPath;
  final String dir;
  final String name;
  const _HookEditor({
    required this.repoPath,
    required this.dir,
    required this.name,
  });

  @override
  ConsumerState<_HookEditor> createState() => _HookEditorState();
}

class _HookEditorState extends ConsumerState<_HookEditor> {
  /// Unsaved text holds the dialog open: Escape, the close button and a click
  /// outside all come through the pop below and ask before throwing it away.
  bool _dirty = false;

  Future<void> _confirmClose() async {
    final l = AppLocalizations.of(context);
    final discard = await confirmDestructive(
      ref,
      context,
      title: l.diffDiscardEditsTitle,
      body: l.diffDiscardEditsBody(widget.name),
      confirmLabel: l.discard,
    );
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmClose();
    },
    child: SizedBox(
      height: 460,
      child: FileTextEditor(
        repoPath: widget.dir,
        relPath: widget.name,
        onDirtyChanged: (dirty) => setState(() => _dirty = dirty),
        onSave: (name, text) => reportHookWrite(
          ref,
          AppLocalizations.of(context),
          name,
          ref
              .read(hookActionsProvider(widget.repoPath))
              .save(widget.dir, name, text),
        ),
        onCancel: () => Navigator.of(context).maybePop(),
        footerBuilder: (context, controls) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: controls.saving ? null : controls.save,
              child: Text(AppLocalizations.of(context).save),
            ),
          ),
        ),
      ),
    ),
  );
}

enum _RejectedChoice { manage, skip }

/// Shows what the hook that refused a commit had to say.
///
/// [skipLabel] and [onSkip] offer the caller's way past the hooks — arming the
/// next commit, or retrying a reword — and only for a hook `--no-verify`
/// really skips. [messageKept] says the typed message is still waiting, which
/// holds for the composer but not for a dialog that has already closed.
Future<void> showHookRejectedDialog(
  BuildContext context, {
  required String repoPath,
  required HookRejectedException rejection,
  String? skipLabel,
  Future<void> Function()? onSkip,
  bool messageKept = true,
}) async {
  final l = AppLocalizations.of(context);
  final choice = await showAppModal<_RejectedChoice>(
    context: context,
    title: l.hkRejectedTitle(rejection.hook),
    icon: Icons.block,
    width: 640,
    body: _HookTranscript(rejection: rejection, messageKept: messageKept),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(_RejectedChoice.manage),
          child: Text(l.hkManage),
        ),
      ),
      // Offered only where it would work: some hooks run despite
      // --no-verify, and getting past one of those this way just fails again.
      if (skipLabel != null &&
          onSkip != null &&
          noVerifyHooks.contains(rejection.hook))
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).pop(_RejectedChoice.skip),
            child: Text(skipLabel),
          ),
        ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.close),
        ),
      ),
    ],
  );
  switch (choice) {
    case _RejectedChoice.skip:
      await onSkip?.call();
    case _RejectedChoice.manage:
      if (context.mounted) await showHooksPanel(context, repoPath);
    case null:
      break;
  }
}

class _HookTranscript extends StatelessWidget {
  final HookRejectedException rejection;
  final bool messageKept;
  const _HookTranscript({required this.rejection, required this.messageKept});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final r = rejection.result;
    // Git hands a commit hook's stdout to stderr, but a hook started some
    // other way may still use both; show whatever came out.
    final output = [
      r?.stderr.trimRight() ?? '',
      r?.stdout.trimRight() ?? '',
    ].where((s) => s.isNotEmpty).join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.hkOutputFrom(rejection.hook),
          style: TextStyle(color: t.textFaint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        // No scroll view of its own: the dialog already scrolls, and a second
        // one inside it stops dead at its end instead of handing the drag on.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.bgApp,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.border),
          ),
          child: output.isEmpty
              ? Text(
                  l.hkNoOutput,
                  style: TextStyle(color: t.textMuted, fontSize: 12),
                )
              : SelectableText(
                  output,
                  style: AppFonts.mns(size: 12, color: t.textPrimary),
                ),
        ),
        if (messageKept) ...[
          const SizedBox(height: 10),
          Text(
            l.hkMessageKept,
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
