// The project navigator collapses to a rail and comes back, the same way the
// history sidebar does.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/files/files_view.dart';
import 'package:mergelio/ui/files/project_nav_panel.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        dirListingProvider.overrideWith(
          (ref, DirKey key) async => const DirListing(
            entries: [DirEntry(name: 'README.md', isDir: false)],
          ),
        ),
        trackedPathsProvider.overrideWith((ref, String _) async => const {}),
        ignoredInDirProvider.overrideWith((ref, DirKey _) async => const {}),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: FilesView(repoPath: '/r')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FilesView)));
}

void main() {
  testWidgets('the navigator starts expanded', (tester) async {
    final c = await _pump(tester);

    expect(find.byType(ProjectNavPanel), findsOneWidget);
    expect(c.read(settingsProvider).filesNavCollapsed, isFalse);
  });

  testWidgets('collapsing hides the tree and leaves a rail', (tester) async {
    final c = await _pump(tester);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectNavPanel), findsNothing);
    expect(find.text('README.md'), findsNothing);
    expect(find.byTooltip('Expand'), findsOneWidget);
    expect(c.read(settingsProvider).filesNavCollapsed, isTrue);
  });

  testWidgets('expanding from the rail brings the tree back', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectNavPanel), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
  });
}
