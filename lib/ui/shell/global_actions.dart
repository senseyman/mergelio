import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/search.dart';
import '../../state/graph_selection.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../../state/search.dart';
import '../../state/workspace.dart';
import '../palette/command_palette.dart';
import '../workspace/branch_switch.dart';
import '../workspace/remote_dialog.dart';

/// App-wide actions shared by the keyboard dispatcher and toolbar buttons, so
/// clicking the toolbar and pressing the shortcut do exactly the same thing.

/// Opens the commit search bar over the graph. No-op without an open repo.
void openGlobalSearch(WidgetRef ref) {
  if (ref.read(workspaceProvider).activeTab == null) return;
  ref.read(searchQueryProvider.notifier).state = const CommitQuery(text: '');
}

/// Opens the command palette with network ops, checkouts and fly-to commits.
void openGlobalPalette(BuildContext context, WidgetRef ref) {
  final path = ref.read(workspaceProvider).activeTab?.path;
  if (path == null) return;
  final actions = ref.read(repoActionsProvider(path));
  final data = ref.read(repoDataProvider(path)).valueOrNull;
  final cmds = <PaletteCommand>[
    PaletteCommand('Fetch', Icons.download_outlined, () => actions.fetch()),
    PaletteCommand('Pull', Icons.south_west, () => actions.pull()),
    PaletteCommand('Push', Icons.north_east, () => actions.push()),
    PaletteCommand(
      'Global search',
      Icons.search,
      () async => openGlobalSearch(ref),
    ),
    PaletteCommand('Add remote…', Icons.dns_outlined, () async {
      if (!context.mounted) return;
      final edit = await showRemoteDialog(
        context,
        title: 'Add remote',
        confirmLabel: 'Add',
        existing: data?.remotes ?? const [],
      );
      if (edit != null) await actions.addRemote(edit.name, edit.url);
    }),
    for (final b in data?.branches ?? const [])
      PaletteCommand(
        'Checkout: ${b.name}',
        Icons.call_split,
        // Routed through activateBranch, not actions.checkout directly, so
        // this consults the same worktree-collision guard as every other
        // checkout entry point. Safe to reuse `context` here: the palette
        // dialog pops itself before running the command (see _Palette._run),
        // so by the time this runs `context` is the long-lived shell context
        // this function was called with, not the palette's own route.
        () => activateBranch(ref, context, path, localBranch: b.name),
      ),
    for (final c in (data?.commits ?? const []).take(200))
      PaletteCommand(
        'Fly to: ${c.shortSha}  ${c.message}',
        Icons.my_location,
        () async => ref.read(selectedCommitProvider.notifier).state = c.sha,
      ),
  ];
  showCommandPalette(context, commands: cmds);
}
