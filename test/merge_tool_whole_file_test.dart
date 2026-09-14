import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/ui/merge/merge_tool.dart';

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// The merge tool must offer a resolution for conflicts with no hunks —
/// otherwise a delete/modify or binary conflict is a dead end.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, ConflictFile file) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit())],
    );
    addTearDown(container.dispose);
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: 'feature',
      files: [file],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('a binary conflict offers both sides and delete', (tester) async {
    await pump(
      tester,
      const ConflictFile(path: 'logo.png', parts: [], binary: true),
    );

    expect(find.text('Keep mine'), findsOneWidget);
    expect(find.text('Keep theirs'), findsOneWidget);
    expect(find.text('Delete file'), findsOneWidget);
    expect(find.textContaining('Binary'), findsOneWidget);
  });

  testWidgets('a side git no longer has is not offered', (tester) async {
    await pump(
      tester,
      const ConflictFile(
        path: 'doc.txt',
        parts: [],
        kind: ConflictKind.deletedByThem,
      ),
    );

    expect(find.text('Keep mine'), findsOneWidget);
    expect(find.text('Keep theirs'), findsNothing);
    expect(find.text('Delete file'), findsOneWidget);
  });

  testWidgets('choosing a side records it on the session', (tester) async {
    final c = await pump(
      tester,
      const ConflictFile(
        path: 'doc.txt',
        parts: [],
        kind: ConflictKind.deletedByUs,
      ),
    );

    await tester.tap(find.text('Keep theirs'));
    await tester.pump();

    final file = c.read(mergeSessionProvider('/r'))!.files.single;
    expect(file.fileChoice, FileResolution.theirs);
    expect(c.read(mergeSessionProvider('/r'))!.allResolved, isTrue);
  });

  testWidgets('the chosen side is marked on the card', (tester) async {
    await pump(
      tester,
      const ConflictFile(
        path: 'logo.png',
        parts: [],
        binary: true,
        fileChoice: FileResolution.ours,
      ),
    );

    expect(find.text('✓ resolved'), findsOneWidget);
  });
}
