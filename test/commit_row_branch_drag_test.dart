import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c({bool head = false}) => Commit(
  sha: 's1',
  message: 'work',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  refs: [if (head) const GitRef(name: 'HEAD', kind: RefKind.head)],
);

void main() {
  Future<List<String>> dragChip(
    WidgetTester tester,
    String chip, {
    bool head = false,
    double width = 1200,
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dropped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              CommitRow(
                commit: _c(head: head),
                branchLabels: const ['feat', 'origin/feat'],
                showBranchLabel: true,
                metrics: const RailMetrics(),
                maxLane: 0,
                cols: const {'branch': true},
                selected: false,
                onTap: () {},
              ),
              DragTarget<String>(
                onAcceptWithDetails: (d) => dropped.add(d.data),
                builder: (_, _, _) =>
                    const SizedBox(key: Key('drop'), width: 400, height: 200),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.drag(
      find.text(chip),
      tester.getCenter(find.byKey(const Key('drop'))) -
          tester.getCenter(find.text(chip)),
    );
    await tester.pumpAndSettle();
    return dropped;
  }

  for (final width in [336.0, 1200.0]) {
    testWidgets('a local branch chip drags its branch name at ${width}px', (
      tester,
    ) async {
      expect(await dragChip(tester, 'feat', width: width), ['feat']);
    });
  }

  testWidgets('a remote branch chip drags its full ref', (tester) async {
    expect(await dragChip(tester, 'origin/feat'), ['origin/feat']);
  });

  testWidgets('the HEAD marker is not draggable', (tester) async {
    expect(await dragChip(tester, 'HEAD', head: true), isEmpty);
  });

  testWidgets('a branch dropped on a chip is handed to that chip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final drops = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              CommitRow(
                commit: _c(),
                branchLabels: const ['feat', 'origin/feat'],
                showBranchLabel: true,
                metrics: const RailMetrics(),
                maxLane: 0,
                cols: const {'branch': true},
                selected: false,
                onTap: () {},
                acceptsBranchDrop: (source, chip) => chip != 'feat',
                onBranchDropped: (source, chip, _) =>
                    drops.add('$source>$chip'),
              ),
              const Draggable<String>(
                data: 'topic',
                feedback: SizedBox(width: 10, height: 10),
                child: Text('source'),
              ),
            ],
          ),
        ),
      ),
    );
    Future<void> dropOn(String chip) async {
      await tester.drag(
        find.text('source'),
        tester.getCenter(find.text(chip)) -
            tester.getCenter(find.text('source')),
      );
      await tester.pumpAndSettle();
    }

    await dropOn('origin/feat');
    expect(drops, ['topic>origin/feat']);
    await dropOn('feat');
    expect(drops, ['topic>origin/feat'], reason: 'the chip refused it');
  });
}
