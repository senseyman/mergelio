import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../state/diff_target.dart';
import '../../state/file_insight.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import '../../l10n/gen/app_localizations.dart';

/// File History / Blame modal with two tabs. History rows open the file's diff
/// at that commit; Blame annotates each line with its last-touching commit.
Future<void> showFileInsight(
  BuildContext context, {
  required String repoPath,
  required String path,
  int initialTab = 0,
}) => showAppModal<void>(
  context: context,
  title: path,
  icon: Icons.history,
  width: 720,
  body: SizedBox(
    height: 480,
    child: _InsightBody(repoPath: repoPath, path: path, initialTab: initialTab),
  ),
);

class _InsightBody extends StatelessWidget {
  final String repoPath;
  final String path;
  final int initialTab;
  const _InsightBody({
    required this.repoPath,
    required this.path,
    required this.initialTab,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Column(
        children: [
          TabBar(
            labelColor: t.textPrimary,
            unselectedLabelColor: t.textFaint,
            indicatorColor: t.accent,
            tabs: [
              Tab(text: l.fiHistory),
              Tab(text: l.wtpBlame),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _HistoryTab(repoPath: repoPath, path: path),
                _BlameTab(repoPath: repoPath, path: path),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  final String repoPath;
  final String path;
  const _HistoryTab({required this.repoPath, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final dateFormat = ref.watch(settingsProvider.select((s) => s.dateFormat));
    return ref
        .watch(fileHistoryProvider((repo: repoPath, path: path)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(l.fiCouldNotLoad, style: TextStyle(color: t.textMuted)),
          ),
          data: (commits) => ListView(
            children: [
              for (final c in commits)
                InkWell(
                  onTap: () {
                    ref.read(diffTargetProvider.notifier).state = DiffTarget(
                      repoPath: repoPath,
                      path: path,
                      commitSha: c.sha,
                    );
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(
                            c.shortSha,
                            style: TextStyle(
                              color: t.textFaint,
                              fontSize: 11.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            c.message,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${c.author} · '
                          '${formatCommitDate(c.date, format: dateFormat)}',
                          style: TextStyle(color: t.textFaint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
  }
}

class _BlameTab extends ConsumerWidget {
  final String repoPath;
  final String path;
  const _BlameTab({required this.repoPath, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(blameProvider((repo: repoPath, path: path)))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              l.fiCouldNotBlame,
              style: TextStyle(color: t.textMuted),
            ),
          ),
          data: (lines) => ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final l = lines[i];
              final newBlock = i == 0 || lines[i - 1].sha != l.sha;
              return Container(
                color: newBlock ? t.bgPanel : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 66,
                      child: Text(
                        newBlock ? l.shortSha : '',
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        newBlock ? l.author : '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.content,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
  }
}
