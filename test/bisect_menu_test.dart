import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/graph_view.dart';

Commit _c(String sha) => Commit(
  sha: sha,
  message: 'msg $sha',
  body: '',
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
);

BisectState _runningState() => const BisectState(
  marks: [
    BisectMark('zzz', BisectKind.bad),
    BisectMark('yyy', BisectKind.good),
  ],
  startBranch: 'main',
  terms: BisectTerms(),
  currentSha: 'aaa',
  revisionsLeft: 1,
  steps: 1,
  firstBad: null,
);

void main() {
  Future<void> openMenu(WidgetTester tester, {BisectState? bisect}) async {
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          bisectStateProvider('/r').overrideWith((ref) => bisect),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GraphList(
              data: RepoData(
                commits: assignLanes([_c('aaa')]),
                branches: const [Branch(name: 'main', current: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.getCenter(find.text('msg aaa'));
    final gesture = await tester.startGesture(row, buttons: kSecondaryButton);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('with no bisect running the menu offers a start item', (
    tester,
  ) async {
    await openMenu(tester, bisect: null);

    expect(find.text('Start bisect from here'), findsOneWidget);
    expect(find.text('Mark as good'), findsNothing);
    expect(find.text('Mark as bad'), findsNothing);
    expect(find.text('Skip this commit'), findsNothing);
  });

  testWidgets('with a bisect running the menu offers the three verdicts', (
    tester,
  ) async {
    await openMenu(tester, bisect: _runningState());

    expect(find.text('Start bisect from here'), findsNothing);
    expect(find.text('Mark as good'), findsOneWidget);
    expect(find.text('Mark as bad'), findsOneWidget);
    expect(find.text('Skip this commit'), findsOneWidget);
  });

  testWidgets('the bisect group sits below the copy group', (tester) async {
    await openMenu(tester, bisect: _runningState());

    final copyY = tester.getTopLeft(find.text('Copy SHA')).dy;
    final bisectY = tester.getTopLeft(find.text('Mark as good')).dy;

    expect(bisectY, greaterThan(copyY));
  });
}
