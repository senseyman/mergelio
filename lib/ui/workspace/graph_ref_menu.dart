import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/graph_ref_filter.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/graph_ref_filter.dart';

/// Context-menu entries hiding [refName] (a full ref name) from the graph of
/// [repoPath], or soloing it, and undoing either.
List<PopupMenuEntry<void>> graphRefMenuItems({
  required BuildContext context,
  required WidgetRef ref,
  required String repoPath,
  required String refName,
}) {
  final l = AppLocalizations.of(context);
  final f =
      ref.read(graphRefFilterProvider(repoPath)).valueOrNull ??
      GraphRefFilter.none;
  final ctl = ref.read(graphRefFilterProvider(repoPath).notifier);
  const style = TextStyle(fontSize: 13);
  return [
    const PopupMenuDivider(),
    PopupMenuItem(
      height: 34,
      onTap: () => ctl.toggleHidden(refName),
      child: Text(
        f.hidden.contains(refName) ? l.grfShow : l.grfHide,
        style: style,
      ),
    ),
    PopupMenuItem(
      height: 34,
      onTap: () => ctl.toggleSolo(refName),
      child: Text(
        f.solo.contains(refName) ? l.grfUnsolo : l.grfSolo,
        style: style,
      ),
    ),
  ];
}

/// Marks a sidebar branch row hidden from or soloed in the graph. Renders
/// nothing for a branch that is neither.
class GraphRefMark extends ConsumerWidget {
  final String repoPath;
  final String refName;
  const GraphRefMark({
    super.key,
    required this.repoPath,
    required this.refName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(graphRefFilterProvider(repoPath)).valueOrNull;
    if (f == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final (icon, tip) = f.hidden.contains(refName)
        ? (Icons.visibility_off, l.grfHiddenMark)
        : f.solo.contains(refName)
        ? (Icons.filter_center_focus, l.grfSoloMark)
        : (null, '');
    if (icon == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tip,
        child: Icon(icon, size: 12, color: t.textFaint),
      ),
    );
  }
}
