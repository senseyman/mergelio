// Unsaved text in the diff sheet's editor outlives the sheet — it is put aside
// on a tab switch — so closing its repository or quitting must still ask.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diff_drafts.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/unsaved_guard.dart';
import 'package:mergelio/ui/diff/diff_draft_guard.dart';

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

/// Records saves instead of writing; a widget test cannot await real file I/O.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  final saved = <String, String>{};
  bool succeeds = true;

  @override
  Future<bool> saveFileText(String relPath, String text) async {
    if (!succeeds) return false;
    saved[relPath] = text;
    return true;
  }
}

const _inA = DiffTarget(repoPath: '/a', path: 'f.txt');

void main() {
  late _RecordingActions actions;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          repoActionsProvider('/a').overrideWith((ref) {
            return actions = _RecordingActions(
              ref,
              '/a',
              GitWriter(_FakeGit(), '/a'),
            );
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: DiffDraftGuard(child: SizedBox())),
        ),
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(DiffDraftGuard)),
    );
    c.read(repoActionsProvider('/a'));
    return c;
  }

  /// Leaves `/a`'s diff open in edit mode holding unsaved text.
  Future<void> draftInA(WidgetTester tester, ProviderContainer c) async {
    c.read(diffTargetProvider.notifier).state = _inA;
    c.read(diffEditingProvider.notifier).state = _inA;
    c.read(diffEditorDirtyProvider.notifier).state = true;
    c
        .read(diffDraftsProvider.notifier)
        .put(
          const DiffDraft(
            target: _inA,
            editor: EditorDraft(
              text: 'typed',
              baseline: EditableFile(text: 'disk'),
            ),
          ),
        );
    await tester.pump();
  }

  /// Runs a close-repository check and answers its prompt with [button].
  Future<bool> answer(
    WidgetTester tester,
    ProviderContainer c,
    String button,
  ) async {
    final asked = c.read(unsavedGuardsProvider).confirm('/a');
    await tester.pumpAndSettle();
    expect(find.textContaining('f.txt'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return asked;
  }

  testWidgets('a repository without unsaved diff edits is not asked about', (
    tester,
  ) async {
    final c = await pump(tester);

    final asked = c.read(unsavedGuardsProvider).confirm('/a');
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsNothing);
    expect(await asked, isTrue);
  });

  testWidgets('Cancel keeps the edits and stops the close', (tester) async {
    final c = await pump(tester);
    await draftInA(tester, c);

    expect(await answer(tester, c, 'Cancel'), isFalse);
    expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed');
    expect(c.read(diffEditorDirtyProvider), isTrue);
  });

  testWidgets('Discard forgets the edits and closes their sheet', (
    tester,
  ) async {
    final c = await pump(tester);
    await draftInA(tester, c);

    expect(await answer(tester, c, 'Discard'), isTrue);
    expect(c.read(diffDraftsProvider), isEmpty);
    expect(c.read(diffTargetProvider), isNull);
    expect(c.read(diffEditingProvider), isNull);
    expect(c.read(diffEditorDirtyProvider), isFalse);
    expect(actions.saved, isEmpty);
  });

  testWidgets('Save writes the edits and lets the close go ahead', (
    tester,
  ) async {
    final c = await pump(tester);
    await draftInA(tester, c);

    expect(await answer(tester, c, 'Save'), isTrue);
    expect(actions.saved, {'f.txt': 'typed'});
    expect(c.read(diffDraftsProvider), isEmpty);
    expect(c.read(diffEditorDirtyProvider), isFalse);
  });

  testWidgets('a save that fails keeps the edits and stops the close', (
    tester,
  ) async {
    final c = await pump(tester);
    await draftInA(tester, c);
    actions.succeeds = false;

    expect(await answer(tester, c, 'Save'), isFalse);
    expect(c.read(diffDraftsProvider)['/a']?.editor.text, 'typed');
  });

  testWidgets('a draft that is settled is no longer asked about', (
    tester,
  ) async {
    final c = await pump(tester);
    await draftInA(tester, c);
    c.read(diffDraftsProvider.notifier).drop('/a');
    await tester.pump();

    final asked = c.read(unsavedGuardsProvider).confirm('/a');
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsNothing);
    expect(await asked, isTrue);
  });

  testWidgets('switching views does not ask: the edits survive it', (
    tester,
  ) async {
    final c = await pump(tester);
    await draftInA(tester, c);

    final asked = c.read(unsavedGuardsProvider).confirm('/a', viewSwitch: true);
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsNothing);
    expect(await asked, isTrue);
  });
}
