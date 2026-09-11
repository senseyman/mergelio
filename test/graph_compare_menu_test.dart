import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/graph_view.dart';

Commit _c(String sha, List<String> parents) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: parents,
);

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    final workspace = WorkspaceController()..openRepo('/r');
    container = ProviderContainer(
      overrides: [
        workspaceProvider.overrideWith((ref) => workspace),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GraphList(
              data: RepoData(
                commits: assignLanes([
                  _c('bbb', const ['aaa']),
                  _c('aaa', const []),
                ]),
                branches: const [Branch(name: 'main', current: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String sha) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('msg $sha')),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('marking a commit arms the comparison', (tester) async {
    await pump(tester);
    await openMenu(tester, 'aaa');

    expect(find.text('Compare with…'), findsNothing);
    await tester.tap(find.text('Mark for comparison'));
    await tester.pumpAndSettle();

    expect(
      container.read(compareMarkProvider),
      const CompareMark(repoPath: '/r', sha: 'aaa'),
    );
  });

  testWidgets('the second commit completes the comparison', (tester) async {
    await pump(tester);
    await openMenu(tester, 'aaa');
    await tester.tap(find.text('Mark for comparison'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'bbb');
    await tester.tap(find.text('Compare with aaa'));
    await tester.pumpAndSettle();

    expect(
      container.read(compareTargetProvider),
      const CompareTarget(repoPath: '/r', from: 'aaa', to: 'bbb'),
    );
    // The mark is spent, so the next right-click starts a fresh comparison.
    expect(container.read(compareMarkProvider), isNull);
  });

  testWidgets('a mark left in another repository is not offered', (
    tester,
  ) async {
    await pump(tester);
    container.read(compareMarkProvider.notifier).state = const CompareMark(
      repoPath: '/elsewhere',
      sha: 'aaa',
    );

    await openMenu(tester, 'bbb');

    expect(find.textContaining('Compare with'), findsNothing);
  });

  testWidgets('the marked commit offers clearing the mark, not comparing', (
    tester,
  ) async {
    await pump(tester);
    await openMenu(tester, 'aaa');
    await tester.tap(find.text('Mark for comparison'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'aaa');

    expect(find.textContaining('Compare with'), findsNothing);
    expect(find.text('Mark for comparison'), findsNothing);
    expect(find.text('Clear comparison mark'), findsOneWidget);
  });

  testWidgets('clearing the mark takes the comparison offer away', (
    tester,
  ) async {
    await pump(tester);
    await openMenu(tester, 'aaa');
    await tester.tap(find.text('Mark for comparison'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'aaa');
    await tester.tap(find.text('Clear comparison mark'));
    await tester.pumpAndSettle();
    expect(container.read(compareMarkProvider), isNull);

    await openMenu(tester, 'bbb');

    expect(find.textContaining('Compare with'), findsNothing);
    expect(find.text('Mark for comparison'), findsOneWidget);
  });
}
