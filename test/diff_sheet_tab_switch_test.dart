import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_drafts.dart';
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
const _inB = DiffTarget(repoPath: '/b', path: 'g.txt');

DiffDraft _draft(DiffTarget target, String text) => DiffDraft(
  target: target,
  editor: EditorDraft(
    text: text,
    baseline: const EditableFile(text: 'disk'),
  ),
);

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

/// Opens [target] in edit mode holding [text] that is not on disk, the way
/// the sheet and its editor leave things.
void _editDirty(ProviderContainer c, DiffTarget target, String text) {
  c.read(diffTargetProvider.notifier).state = target;
  c.read(diffEditingProvider.notifier).state = target;
  c.read(diffEditorDirtyProvider.notifier).state = true;
  c.read(diffDraftsProvider.notifier).put(_draft(target, text));
}

/// Whether the sheet is in edit mode on [target] with unsaved text.
Matcher _editingDirty(DiffTarget target) => isA<ProviderContainer>()
    .having((c) => c.read(diffTargetProvider), 'target', target)
    .having((c) => c.read(diffEditingProvider), 'editing', target)
    .having((c) => c.read(diffEditorDirtyProvider), 'dirty', isTrue);

/// Whether nothing is open in the sheet.
Matcher get _closed => isA<ProviderContainer>()
    .having((c) => c.read(diffTargetProvider), 'target', isNull)
    .having((c) => c.read(diffEditingProvider), 'editing', isNull)
    .having((c) => c.read(diffEditorDirtyProvider), 'dirty', isFalse);

/// Lets a test take the centre column down and bring it back, as Files mode
/// and the dashboard do.
final _slotShown = StateProvider<bool>((_) => true);

Widget _harness(WorkspaceController workspace) => ProviderScope(
  overrides: [
    gitServiceProvider.overrideWithValue(_FakeGit()),
    workspaceProvider.overrideWith((ref) => workspace),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
    // The real provider reads the working tree, which a widget test's
    // fake-async zone never lets complete.
    editableFileForPathProvider.overrideWith(
      (ref, FileRef _) async => const EditableFile(text: 'disk'),
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
          return SizedBox(
            height: 400,
            child: Stack(
              children: [
                if (ref.watch(_slotShown))
                  const DiffSheetSlot(availableHeight: 400),
              ],
            ),
          );
        },
      ),
    ),
  ),
);

/// The editor's caret blinks forever, so pumpAndSettle never returns once
/// edit mode is open. Pump past the slide instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  group('switching tabs', () {
    test('closes a diff that has no unsaved edits', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;

      workspace.setActive(2);

      expect(c, _closed);
    });

    test('leaves edit mode when the editor holds nothing unsaved', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      c.read(diffTargetProvider.notifier).state = _inA;
      c.read(diffEditingProvider.notifier).state = _inA;

      workspace.setActive(2);

      expect(c, _closed);
    });

    test('puts unsaved edits aside instead of dropping them', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');

      workspace.setActive(2);

      expect(c, _closed);
      expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed');
    });

    test('the other repository opens its own diffs while edits wait', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');
      workspace.setActive(2);

      c.read(diffTargetProvider.notifier).state = _inB;

      expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed');
    });

    test('coming back reopens the edits that were put aside', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');
      workspace.setActive(2);
      c.read(diffTargetProvider.notifier).state = _inB;

      workspace.setActive(1);

      expect(c, _editingDirty(_inA));
      expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed');
    });

    test('each repository gets its own unsaved edits back', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed in a');
      workspace.setActive(2);
      _editDirty(c, _inB, 'typed in b');

      workspace.setActive(1);
      expect(c, _editingDirty(_inA));

      workspace.setActive(2);
      expect(c, _editingDirty(_inB));
      expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed in a');
      expect(c.read(diffDraftsProvider)['/b']?.editor.text, 'typed in b');
    });

    test('re-selecting the active tab keeps the diff', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');

      workspace.setActive(1);

      expect(c, _editingDirty(_inA));
    });

    test('closing a repository forgets the edits it had put aside', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');
      workspace.setActive(2);

      workspace.closeTab(1);

      expect(c.read(diffDraftsProvider), isEmpty);
    });

    test('opening another file of the repository drops the stale draft', () {
      final workspace = _twoTabs();
      final c = _container(workspace);
      _editDirty(c, _inA, 'typed');

      c.read(diffTargetProvider.notifier).state = const DiffTarget(
        repoPath: '/a',
        path: 'other.txt',
      );

      expect(c.read(diffDraftsProvider), isEmpty);
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

      expect(find.byType(DiffSheet, skipOffstage: false), findsNothing);
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

    /// Opens `/a`'s diff in the editor and types into it.
    Future<ProviderContainer> typeIntoA(WidgetTester tester) async {
      final workspace = _twoTabs();
      await tester.pumpWidget(_harness(workspace));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DiffSheetSlot)),
      );
      c.read(diffTargetProvider.notifier).state = _inA;
      c.read(diffEditingProvider.notifier).state = _inA;
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'typed');
      await _settle(tester);
      return c;
    }

    testWidgets('typed text comes back after a trip to another tab', (
      tester,
    ) async {
      final c = await typeIntoA(tester);
      final workspace = c.read(workspaceProvider.notifier);

      workspace.setActive(2);
      await _settle(tester);
      expect(find.byType(DiffSheet, skipOffstage: false), findsNothing);

      workspace.setActive(1);
      await _settle(tester);
      expect(find.text('typed'), findsOneWidget);
      expect(c.read(diffEditorDirtyProvider), isTrue);
    });

    testWidgets('typed text survives the centre column being taken down', (
      tester,
    ) async {
      final c = await typeIntoA(tester);

      c.read(_slotShown.notifier).state = false;
      await _settle(tester);
      c.read(_slotShown.notifier).state = true;
      await _settle(tester);

      expect(find.text('typed'), findsOneWidget);
      expect(c.read(diffEditorDirtyProvider), isTrue);
    });
  });
}
