import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/undo_stack.dart';
import '../../state/workspace.dart';
import '../common/confirm.dart';
import '../common/dialogs.dart';
import 'repo_op_dialogs.dart';
import 'shell_widgets.dart';

/// Bottom action bar: undo/redo pinned left, git operations centred with a
/// single divider between the network and branch-ops groups. The network
/// buttons open split menus upward and run against the active repo's remote.
class AppBottomBar extends ConsumerWidget {
  const AppBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final path = ref.watch(workspaceProvider).activeTab?.path;
    final remotes = path == null
        ? const <String>[]
        : (ref.watch(repoDataProvider(path)).valueOrNull?.remotes ??
              const <String>[]);
    final hasRemote = path != null && remotes.isNotEmpty;
    final busy = ref.watch(busyProvider) != null;
    final actions = path == null ? null : ref.read(repoActionsProvider(path));
    final undo = path == null
        ? const UndoState()
        : ref.watch(undoProvider(path));

    // A disabled network op explains the actual reason it is unavailable.
    void whyDisabled() {
      final reason = path == null
          ? 'Open a repository first'
          : busy
          ? 'An operation is already running'
          : 'No remote configured';
      ref.read(toastProvider.notifier).show(reason, kind: ToastKind.warning);
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: t.bgApp,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                BarIconButton(
                  icon: Icons.undo,
                  tooltip: undo.canUndo
                      ? 'Undo ${undo.undoLabel} (⌘Z)'
                      : 'Undo (⌘Z)',
                  onPressed: undo.canUndo && actions != null
                      ? actions.undo
                      : null,
                ),
                BarIconButton(
                  icon: Icons.redo,
                  tooltip: undo.canRedo
                      ? 'Redo ${undo.redoLabel} (⌘⇧Z)'
                      : 'Redo (⌘⇧Z)',
                  onPressed: undo.canRedo && actions != null
                      ? actions.redo
                      : null,
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _OpButton(
                          icon: Icons.download_outlined,
                          label: l.opFetch,
                          enabled: hasRemote && !busy,
                          onDisabledTap: whyDisabled,
                          items: () => [
                            _Op(
                              'Fetch origin',
                              () => actions!.fetch(remote: 'origin'),
                            ),
                            _Op('Fetch all remotes', () => actions!.fetch()),
                          ],
                        ),
                        _OpButton(
                          icon: Icons.south_west,
                          label: l.opPull,
                          enabled: hasRemote && !busy,
                          onDisabledTap: whyDisabled,
                          items: () => [
                            _Op(l.opPull, () => actions!.pull()),
                            _Op(
                              l.opPullRebase,
                              () => actions!.pull(rebase: true),
                            ),
                            // Fetch every remote, then pull the current
                            // branch's upstream.
                            _Op('Pull (all remotes)', () async {
                              await actions!.fetch();
                              await actions.pull();
                            }),
                          ],
                        ),
                        _OpButton(
                          icon: Icons.north_east,
                          label: l.opPush,
                          enabled: hasRemote && !busy,
                          onDisabledTap: whyDisabled,
                          items: () => [
                            _Op(l.opPushOrigin, () => actions!.push()),
                            _Op(l.opForcePush, () async {
                              final ok = await confirmDestructive(
                                ref,
                                context,
                                title: 'Force-push?',
                                body:
                                    'This overwrites the remote branch with your local '
                                    'history (using --force-with-lease, which still '
                                    'refuses if the remote moved unexpectedly).',
                                confirmLabel: 'Force-push',
                              );
                              if (ok) await actions!.push(force: true);
                            }, danger: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const BarSeparator(),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BarTextButton(
                          icon: Icons.call_split,
                          label: 'Branch',
                          onPressed: path == null
                              ? null
                              : () => showBranchDialog(context, ref, path),
                        ),
                        BarTextButton(
                          icon: Icons.merge,
                          label: 'Merge',
                          onPressed: path == null
                              ? null
                              : () => showMergeDialog(context, ref, path),
                        ),
                        BarTextButton(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stash',
                          onPressed: path == null
                              ? null
                              : () => showStashDialog(context, ref, path),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single entry in a network split menu.
class _Op {
  final String label;
  final Future<void> Function() run;
  final bool danger;
  const _Op(this.label, this.run, {this.danger = false});
}

/// Bar button that opens its menu upward (there is no room below at the screen
/// bottom, so showMenu flips it up). Disabled buttons still explain themselves.
class _OpButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onDisabledTap;
  final List<_Op> Function() items;

  const _OpButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onDisabledTap,
    required this.items,
  });

  void _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    // Anchor at the button's top edge; at the screen bottom the menu flips up.
    final topCentre = box.localToGlobal(Offset(box.size.width / 2, 0));
    final t = context.tokens;
    // Uses the shared themed menu helper for a consistent app look.
    showContextMenu<_Op>(
      context: context,
      position: topCentre,
      items: [
        for (final op in items())
          PopupMenuItem<_Op>(
            value: op,
            height: 38,
            child: Text(
              op.label,
              style: TextStyle(
                fontSize: 13,
                color: op.danger ? t.danger : t.textPrimary,
              ),
            ),
          ),
      ],
    ).then((op) => op?.run());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.rButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.rButton),
        hoverColor: t.hover,
        onTap: enabled ? () => _open(context) : onDisabledTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: enabled ? t.textMuted : t.textFaint),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: enabled ? t.textPrimary : t.textFaint,
                ),
              ),
              Icon(Icons.arrow_drop_up, size: 16, color: t.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
