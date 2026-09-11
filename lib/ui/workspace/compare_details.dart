import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/compare_target.dart';
import '../../state/diff_target.dart';
import '../../state/settings_controller.dart';
import '../common/change_file_row.dart';
import '../common/file_tree_view.dart';

/// Right panel content while two revisions are being compared: the pair being
/// read, and every file that differs between them. Read-only — a comparison
/// has no index to stage into, so tapping a file opens the diff sheet on the
/// two-revision diff.
class CompareDetails extends ConsumerWidget {
  const CompareDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final target = ref.watch(compareTargetProvider);
    if (target == null) return const SizedBox.shrink();
    final files = ref.watch(compareFilesProvider(target));

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
                  l.cmpTitle,
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
                  tooltip: l.cmpSwap,
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () =>
                      ref.read(compareTargetProvider.notifier).state =
                          target.swapped,
                ),
                IconButton(
                  iconSize: 15,
                  tooltip: l.close,
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      ref.read(compareTargetProvider.notifier).state = null,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _Sides(from: target.fromLabel, to: target.toLabel),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      l.cdChangedFiles,
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    const FileViewToggle(),
                  ],
                ),
                const SizedBox(height: 6),
                files.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    l.cmpCouldNotRead,
                    style: TextStyle(color: t.textMuted, fontSize: 12),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Text(
                        l.cmpNoDifferences,
                        style: TextStyle(color: t.textFaint, fontSize: 12),
                      );
                    }
                    final tree = ref.watch(
                      settingsProvider.select((s) => s.filesAsTree),
                    );
                    final byPath = {for (final f in list) f.path: f};
                    return FileTreeView(
                      paths: [for (final f in list) f.path],
                      tree: tree,
                      fileRow: (path, depth) => ChangeFileRow(
                        file:
                            byPath[path] ??
                            CommitFileChange(
                              path: path,
                              change: GitChange.modified,
                            ),
                        repoPath: target.repoPath,
                        indent: FileTreeView.indent(depth),
                        inTree: tree,
                        onTap: () =>
                            ref.read(diffTargetProvider.notifier).state = target
                                .fileTarget(path),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two revisions being compared, read left to right.
class _Sides extends StatelessWidget {
  final String from;
  final String to;
  const _Sides({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget side(String label) => Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: t.border),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Row(
      children: [
        side(from),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward, size: 13, color: t.textFaint),
        ),
        side(to),
      ],
    );
  }
}
