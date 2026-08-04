import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/diff/syntax_style.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      return const GitResult(0, '''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old line
+new line
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Records saves instead of touching the disk. Writing for real is covered by
/// file_editor_save_test.dart; a widget test cannot await real file I/O.
class _RecordingActions extends RepoActions {
  _RecordingActions(super.ref, super.path, super.writer);

  String? saved;

  /// Set false to exercise a refused save (busy repo, unwritable file).
  bool succeeds = true;

  @override
  Future<bool> saveFileText(String relPath, String text) async {
    if (!succeeds) return false;
    saved = text;
    return true;
  }
}

/// The editor focuses a TextField whose caret blinks forever, so pumpAndSettle
/// never returns once edit mode is open. Pump a bounded number of frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  // Stays null until something actually reads the actions provider, which only
  // a save does — the cancel paths must not reach it.
  _RecordingActions? actions;
  setUp(() => actions = null);

  Future<void> open(
    WidgetTester tester, {
    String? commitSha,
    EditableFile file = const EditableFile(text: 'keep\nnew line\n'),
  }) async {
    final target = DiffTarget(
      repoPath: '/r',
      path: 'a.txt',
      commitSha: commitSha,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_FakeGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          // The real provider reads the working tree; a widget test's
          // fake-async zone never lets that I/O complete.
          editableFileForPathProvider(
            FileRef(target.repoPath, target.path),
          ).overrideWith((ref) async => file),
          repoActionsProvider('/r').overrideWith((ref) {
            final a = _RecordingActions(ref, '/r', GitWriter(_FakeGit(), '/r'));
            actions = a;
            return a;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DiffSheet)),
    );
    container.read(diffTargetProvider.notifier).state = target;
    // Build the fake actions now so a test can arrange its behaviour; nothing
    // reads the provider until a save would happen.
    container.read(repoActionsProvider('/r'));
    await tester.pumpAndSettle();
  }

  Future<void> enterEditMode(WidgetTester tester) async {
    await tester.tap(find.text('Edit'));
    await settle(tester);
  }

  testWidgets('an uncommitted file offers Edit', (tester) async {
    await open(tester);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('a commit diff offers no Edit', (tester) async {
    await open(tester, commitSha: 'abc1234');
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('Edit loads the working-tree file into a field', (tester) async {
    await open(tester);
    await enterEditMode(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'keep\nnew line\n');
  });

  testWidgets('the editor highlights what it shows', (tester) async {
    await open(tester, file: const EditableFile(text: 'const x = 1;\n'));
    await enterEditMode(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    final controller = field.controller;
    expect(controller, isA<SyntaxHighlightingController>());

    final span = controller!.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      style: const TextStyle(),
      withComposing: false,
    );
    final keywordColours = <Color?>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text == 'const') {
        keywordColours.add(s.style?.color);
      }
      return true;
    });
    expect(
      keywordColours.single,
      syntaxColor(AppTokens.dark(), SyntaxKind.keyword),
    );
  });

  testWidgets('the staging buttons step aside while editing', (tester) async {
    await open(tester);
    await enterEditMode(tester);

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Stage file'), findsNothing);
  });

  testWidgets('Save writes the edited text and leaves edit mode', (
    tester,
  ) async {
    await open(tester);
    await enterEditMode(tester);

    await tester.enterText(find.byType(TextField), 'keep\nedited here\n');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(actions?.saved, 'keep\nedited here\n');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a refused save keeps the editor open with the text', (
    tester,
  ) async {
    await open(tester);
    await enterEditMode(tester);
    actions!.succeeds = false;

    await tester.enterText(find.byType(TextField), 'keep\nnot written\n');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    // Losing the typed text because the repo was busy would be silent damage.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'keep\nnot written\n');
    expect(find.text('Save'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull, reason: 'Save must not stay disabled');
  });

  testWidgets('closing the sheet with unsaved edits asks first', (
    tester,
  ) async {
    await open(tester);
    await enterEditMode(tester);

    await tester.enterText(find.byType(TextField), 'keep\nunsaved\n');
    await settle(tester);
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    expect(find.text('Discard edits?'), findsOneWidget);
  });

  testWidgets('closing the sheet with no edits does not ask', (tester) async {
    await open(tester);
    await enterEditMode(tester);

    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    expect(find.text('Discard edits?'), findsNothing);
  });

  testWidgets('Cancel with no edits leaves without asking', (tester) async {
    await open(tester);
    await enterEditMode(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(actions?.saved, isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Cancel asks before dropping unsaved edits', (tester) async {
    await open(tester);
    await enterEditMode(tester);

    await tester.enterText(find.byType(TextField), 'discard me\n');
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.text('Discard edits?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await settle(tester);

    expect(actions?.saved, isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a binary file cannot be edited', (tester) async {
    await open(
      tester,
      file: const EditableFile(blocker: 'Binary file — cannot be edited here'),
    );
    await tester.tap(find.text('Edit'));
    await settle(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Binary file'), findsOneWidget);
  });
}
