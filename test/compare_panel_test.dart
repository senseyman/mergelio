import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/compare_details.dart';

const _files = [
  CommitFileChange(path: 'lib/a.dart', change: GitChange.added),
  CommitFileChange(path: 'lib/b.dart', change: GitChange.modified),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<CommitFileChange> files = _files,
  CompareTarget? target,
}) async {
  final container = ProviderContainer(
    overrides: [
      compareFilesProvider.overrideWith((ref, key) async => files),
      settingsProvider.overrideWith(
        (ref) => SettingsController(
          InMemorySettingsRepository(),
          const AppSettings(filesAsTree: false),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(compareTargetProvider.notifier).state =
      target ??
      const CompareTarget(repoPath: '/repo', from: 'main', to: 'feature');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CompareDetails()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('names both sides and lists the files that differ', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/b.dart'), findsOneWidget);
  });

  testWidgets('the revision pills size to their text, not to the panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      target: const CompareTarget(
        repoPath: '/repo',
        from: 'main',
        to: 'feature',
      ),
    );

    final pill = tester.getSize(
      find
          .ancestor(of: find.text('main'), matching: find.byType(Container))
          .first,
    );
    expect(pill.width, lessThan(120));
  });

  testWidgets('an empty comparison says so', (tester) async {
    await _pump(tester, files: const []);

    expect(find.text('No differences'), findsOneWidget);
  });

  testWidgets('tapping a file opens it as a two-ref diff', (tester) async {
    final c = await _pump(tester);

    await tester.tap(find.text('lib/b.dart'));
    await tester.pumpAndSettle();

    expect(
      c.read(diffTargetProvider),
      const DiffTarget(
        repoPath: '/repo',
        path: 'lib/b.dart',
        baseRev: 'main',
        commitSha: 'feature',
      ),
    );
  });

  testWidgets('swap reverses the comparison', (tester) async {
    final c = await _pump(tester);

    await tester.tap(find.byTooltip('Swap sides'));
    await tester.pumpAndSettle();

    expect(c.read(compareTargetProvider)!.from, 'feature');
    expect(c.read(compareTargetProvider)!.to, 'main');
  });

  testWidgets('closing clears the comparison', (tester) async {
    final c = await _pump(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(c.read(compareTargetProvider), isNull);
  });
}
