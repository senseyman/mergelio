import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_tab_switch.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/workspace/workspace_view.dart';

/// Answers every git call with empty output; the sheet only needs to mount.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _inA = DiffTarget(repoPath: '/a', path: 'f.txt');

/// Two tabs, `/a` (id 1) and `/b` (id 2), with `/a` active.
WorkspaceController _twoTabs() => WorkspaceController()
  ..openRepo('/a')
  ..openRepo('/b')
  ..setActive(1);

ProviderContainer _container(WorkspaceController workspace) {
  final c = ProviderContainer(
    overrides: [workspaceProvider.overrideWith((ref) => workspace)],
  );
  addTearDown(c.dispose);
  c.listen(diffTabSwitchProvider, (_, _) {});
  return c;
}

Widget _harness(WorkspaceController workspace) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    workspaceProvider.overrideWith((ref) => workspace),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) {
          ref.watch(diffTabSwitchProvider);
          return const SizedBox(
            height: 400,
            child: Stack(children: [DiffSheetSlot(availableHeight: 400)]),
          );
        },
      ),
    ),
  ),
);

void main() {
  group('switching tabs', () {
    test('closes a diff that has no unsaved edits', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;

      workspace.setActive(2);

      expect(c.read(diffTargetProvider), isNull);
    });

    test('leaves edit mode when the editor holds nothing unsaved', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;
      c.read(diffEditingProvider.notifier).state = _inA;

      workspace.setActive(2);

      expect(c.read(diffTargetProvider), isNull);
      expect(c.read(diffEditingProvider), isNull);
    });

    test('keeps a diff whose editor holds unsaved text', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;
      c.read(diffEditingProvider.notifier).state = _inA;
      c.read(diffEditorDirtyProvider.notifier).state = true;

      workspace.setActive(2);

      expect(c.read(diffTargetProvider), _inA);
      expect(c.read(diffEditingProvider), _inA);
      expect(c.read(diffEditorDirtyProvider), isTrue);
    });

    test('re-selecting the active tab keeps the diff', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;

      workspace.setActive(1);

      expect(c.read(diffTargetProvider), _inA);
    });
  });

  group('DiffSheetSlot', () {
    testWidgets('shows the diff of the active repository', (tester) async {
      final workspace = _twoTabs();
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      await tester.pumpAndSettle();

      expect(find.byType(DiffSheet), findsOneWidget);
    });

    testWidgets('never shows a diff from another repository', (tester) async {
      final workspace = _twoTabs()..setActive(2);
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      await tester.pumpAndSettle();

      expect(find.byType(DiffSheet), findsNothing);
    });

    testWidgets('closes the sheet on a tab switch', (tester) async {
      final workspace = _twoTabs();
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      await tester.pumpAndSettle();

      workspace.setActive(2);
      await tester.pumpAndSettle();

      expect(find.byType(DiffSheet, skipOffstage: false), findsNothing);
    });

    testWidgets('hides unsaved edits elsewhere and brings them back intact', (
      tester,
    ) async {
      final workspace = _twoTabs();
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      await tester.pumpAndSettle();
      // The sheet's element standing in for the editor's typed text: if it
      // survives the trip, so does everything mounted beneath it.
      final before = tester.element(find.byType(DiffSheet));
      c.read(diffEditingProvider.notifier).state = _inA;
      c.read(diffEditorDirtyProvider.notifier).state = true;

      // The editor reads the file from disk, which never resolves here, so
      // step past the slide instead of waiting for everything to settle.
      workspace.setActive(2);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DiffSheet), findsNothing);
      expect(find.byType(DiffSheet, skipOffstage: false), findsOneWidget);

      workspace.setActive(1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DiffSheet), findsOneWidget);
      expect(tester.element(find.byType(DiffSheet)), same(before));
    });

    testWidgets('a hidden sheet holds no keyboard focus', (tester) async {
      final workspace = _twoTabs();
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      await tester.pumpAndSettle();
      c.read(diffEditingProvider.notifier).state = _inA;
      c.read(diffEditorDirtyProvider.notifier).state = true;

      workspace.setActive(2);
      await tester.pump(const Duration(milliseconds: 300));

      final sheet = find.byType(DiffSheet, skipOffstage: false);
      final focused = FocusManager.instance.primaryFocus?.context;
      final inSheet =
          focused != null &&
          find
              .descendant(of: sheet, matching: find.byWidget(focused.widget))
              .evaluate()
              .isNotEmpty;
      expect(inSheet, isFalse);
    });
  });
}
