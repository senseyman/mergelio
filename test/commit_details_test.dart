import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';

final _commit = Commit(
  sha: 'abcdef1234567890',
  message: 'feat: something',
  author: 'Tester',
  authorEmail: 't@example.com',
  date: DateTime(2026, 7, 2),
  parents: const ['1111111aaaa'],
  signed: true,
  sigStatus: 'G',
);

Widget _harness({List<CommitFileChange>? files, bool hasWip = false}) =>
    ProviderScope(
      overrides: [
        commitFilesProvider.overrideWith(
          (ref, key) async =>
              files ??
              const [CommitFileChange(path: 'x', change: GitChange.modified)],
        ),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(filesAsTree: false),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: CommitDetails(
            repoPath: '/repo',
            commit: _commit,
            hasWip: hasWip,
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows metadata, signature and changed files', (tester) async {
    await tester.pumpWidget(
      _harness(
        files: const [
          CommitFileChange(path: 'lib/a.dart', change: GitChange.added),
          CommitFileChange(
            path: 'lib/new.dart',
            change: GitChange.renamed,
            origPath: 'lib/old.dart',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feat: something'), findsOneWidget);
    expect(find.text('Tester <t@example.com>'), findsOneWidget);
    expect(find.text('Jul 2, 2026'), findsOneWidget);
    expect(find.text('abcdef1'), findsOneWidget);
    expect(find.text('1111111'), findsOneWidget);
    expect(find.text('Verified signature'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/old.dart → lib/new.dart'), findsOneWidget);
  });

  testWidgets('WIP shortcut appears only when the tree is dirty and selects '
      'the WIP row', (tester) async {
    await tester.pumpWidget(_harness(hasWip: false));
    await tester.pumpAndSettle();
    expect(find.text('‹ WIP'), findsNothing);

    await tester.pumpWidget(_harness(hasWip: true));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CommitDetails)),
    );
    await tester.tap(find.text('‹ WIP'));
    await tester.pump();
    expect(container.read(selectedCommitProvider), wipSelection);
  });
}
