import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/diff.dart';
import '../../domain/git/line_history.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/diff_target.dart';
import '../../state/file_insight.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';

/// History of one line range (`git log -L`): every commit that changed the
/// range, newest first, each showing what it did to those lines. A row opens
/// the commit's full diff for the file, the way the File History list does.
///
/// [start] and [end] are read against [rev] — the revision the numbers came
/// from. Numbers taken off a working-tree diff count uncommitted lines, so
/// edits above the range shift what HEAD reports.
Future<void> showLineHistory(
  BuildContext context, {
  required String repoPath,
  required String path,
  required int start,
  required int end,
  String rev = 'HEAD',
}) {
  final l = AppLocalizations.of(context);
  // One line reads as a line, not a range; the two labels differ by more than
  // an "s" in other languages.
  final title = start == end
      ? l.lhTitleLine(path, '$start')
      : l.lhTitleRange(path, '$start–$end');
  return showAppModal<void>(
    context: context,
    title: title,
    icon: Icons.manage_search,
    width: 720,
    body: SizedBox(
      height: 480,
      child: _LineHistoryBody(
        repoPath: repoPath,
        path: path,
        start: start,
        end: end,
        rev: rev,
      ),
    ),
  );
}

class _LineHistoryBody extends ConsumerWidget {
  final String repoPath;
  final String path;
  final int start;
  final int end;
  final String rev;

  const _LineHistoryBody({
    required this.repoPath,
    required this.path,
    required this.start,
    required this.end,
    required this.rev,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return ref
        .watch(
          lineHistoryProvider((
            repo: repoPath,
            path: path,
            start: start,
            end: end,
            rev: rev,
          )),
        )
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(l.lhCouldNotLoad, style: TextStyle(color: t.textMuted)),
          ),
          data: (entries) => entries.isEmpty
              ? Center(
                  child: Text(
                    l.lhNoChanges,
                    style: TextStyle(color: t.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _EntryTile(
                    entry: entries[i],
                    // The range's history can cross a rename, so the diff opens
                    // on the name the file had in that commit.
                    onOpen: () {
                      ref.read(diffTargetProvider.notifier).state = DiffTarget(
                        repoPath: repoPath,
                        path: entries[i].path,
                        commitSha: entries[i].commit.sha,
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ),
        );
  }
}

class _EntryTile extends ConsumerWidget {
  final LineHistoryEntry entry;
  final VoidCallback onOpen;

  const _EntryTile({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final fmt = ref.watch(settingsProvider.select((s) => s.dateFormat));
    final c = entry.commit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.message,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.textPrimary, fontSize: 13),
                      ),
                      Text(
                        '${c.author} · ${formatCommitDate(c.date, format: fmt, offset: c.dateOffset)}',
                        style: TextStyle(color: t.textFaint, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  entry.path,
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final hunk in entry.hunks)
          for (final line in hunk.lines) _RangeLine(line: line),
        Divider(height: 1, color: t.border),
      ],
    );
  }
}

/// One line of the range's diff, tinted by what the commit did to it.
class _RangeLine extends StatelessWidget {
  final DiffLine line;
  const _RangeLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = switch (line.type) {
      DiffLineType.add => t.addBg,
      DiffLineType.del => t.delBg,
      DiffLineType.context => null,
    };
    final sign = switch (line.type) {
      DiffLineType.add => '+',
      DiffLineType.del => '-',
      DiffLineType.context => ' ',
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${line.newNo ?? line.oldNo ?? ''}',
              textAlign: TextAlign.right,
              style: TextStyle(color: t.textFaint, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            sign,
            style: TextStyle(
              color: t.textFaint,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              line.text,
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
  }
}
