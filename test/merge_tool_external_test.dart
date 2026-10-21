import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/ui/merge/merge_tool.dart';

/// Answers the tool config read with a merge tool, and everything else with
/// nothing — so git reports no unmerged paths once the tool has run.
class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(a);
    if (a.first == 'config') {
      return const GitResult(0, 'merge.tool\nbc\x00', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<(_FakeGit, ProviderContainer)> pump(
    WidgetTester tester, {
    List<ConflictFile> files = const [ConflictFile(path: 'a.txt', parts: [])],
    Locale locale = const Locale('en'),
    double width = 1400,
  }) async {
    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final git = _FakeGit();
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: 'feature',
      files: files,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pump();
    return (git, container);
  }

  List<String>? mergetoolCall(_FakeGit git) =>
      git.calls.where((c) => c.first == 'mergetool').firstOrNull;

  testWidgets('the header button hands the open file to the merge tool', (
    tester,
  ) async {
    final (git, _) = await pump(tester);
    await tester.tap(find.byTooltip('Open a.txt in merge tool'));
    // Lets the toasts and the coalesced refresh run out.
    await tester.pump(const Duration(seconds: 5));
    expect(mergetoolCall(git), ['mergetool', '--no-prompt', '--', 'a.txt']);
    // Nothing past staging was asked of git.
    expect(
      git.calls.where((c) => c.first == 'commit' || c.contains('--continue')),
      isEmpty,
    );
  });

  testWidgets('a file row offers the merge tool, not the editor', (
    tester,
  ) async {
    final (git, _) = await pump(tester);
    await tester.tap(find.text('a.txt').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    // Resolve writes the app's own result over the file, so an edit made in
    // the editor would be lost.
    expect(find.text('Open in editor'), findsNothing);
    await tester.tap(find.text('Open in merge tool'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(mergetoolCall(git), isNotNull);
  });

  testWidgets('a submodule conflict offers no merge tool', (tester) async {
    final (git, _) = await pump(
      tester,
      files: const [ConflictFile(path: 'sub', parts: [], submodule: true)],
    );
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.open_in_new),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('sub').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open in merge tool'), findsNothing);
    expect(git.calls.where((c) => c.first == 'mergetool'), isEmpty);
  });

  testWidgets('a path one side deleted offers no merge tool', (tester) async {
    final (git, _) = await pump(
      tester,
      files: const [
        ConflictFile(path: 'gone', parts: [], kind: ConflictKind.deletedByThem),
      ],
    );
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.open_in_new),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('gone').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open in merge tool'), findsNothing);
    expect(git.calls.where((c) => c.first == 'mergetool'), isEmpty);
  });

  testWidgets('the open file stays open when another one is resolved', (
    tester,
  ) async {
    await pump(
      tester,
      files: const [
        ConflictFile(path: 'a.txt', parts: []),
        ConflictFile(path: 'b.txt', parts: []),
        ConflictFile(path: 'c.txt', parts: []),
      ],
    );
    await tester.tap(find.text('b.txt').first);
    await tester.pump();
    expect(find.byTooltip('Open b.txt in merge tool'), findsOneWidget);
    // The fake reports nothing unmerged, so a.txt leaves the session.
    await tester.tap(find.text('a.txt').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in merge tool'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('a.txt'), findsNothing);
    expect(find.byTooltip('Open b.txt in merge tool'), findsOneWidget);
  });

  testWidgets('the open file being resolved moves on to the next one', (
    tester,
  ) async {
    await pump(
      tester,
      files: const [
        ConflictFile(path: 'a.txt', parts: []),
        ConflictFile(path: 'b.txt', parts: []),
        ConflictFile(path: 'c.txt', parts: []),
      ],
    );
    await tester.tap(find.text('b.txt').first);
    await tester.pump();
    await tester.tap(find.byTooltip('Open b.txt in merge tool'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('Open c.txt in merge tool'), findsOneWidget);
  });

  testWidgets('renders in Ukrainian', (tester) async {
    await pump(tester, locale: const Locale('uk'));
    expect(
      find.byTooltip('Відкрити a.txt в інструменті злиття'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
