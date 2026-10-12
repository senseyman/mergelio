import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/patch_file.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/ui/workspace/apply_patch_dialog.dart';

/// Answers every git call with failure, so a flow that got as far as
/// running git would show it, and no real git ever runs.
class _NoGit implements GitService {
  int calls = 0;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls++;
    return const GitResult(1, '', 'no git here');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

PatchPreview _preview({
  List<String> subjects = const [],
  bool worktree = true,
  bool stage = true,
  ThreeWayCheck threeWay = ThreeWayCheck.unavailable,
  String error = '',
}) => PatchPreview(
  files: const [
    PatchFileStat('lib/a_rather_long_directory_name/some_file.dart', 3, 1),
    PatchFileStat('assets/logo.png', null, null),
  ],
  subjects: subjects,
  worktreeOk: worktree,
  stageOk: stage,
  threeWay: threeWay,
  error: error,
);

void main() {
  late PatchMode? picked;
  late bool closed;

  Future<void> open(
    WidgetTester tester,
    PatchPreview p, {
    double w = 900,
  }) async {
    tester.view.physicalSize = Size(w, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picked = null;
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showApplyPatchDialog(
                  context,
                  fileName: 'series.mbox',
                  preview: p,
                );
                closed = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a mailbox lists its messages and says they are not applied', (
    tester,
  ) async {
    await open(tester, _preview(subjects: ['Fix parser', 'Add test']));
    expect(find.text('series.mbox'), findsOneWidget);
    expect(find.text('Fix parser'), findsOneWidget);
    expect(find.text('Add test'), findsOneWidget);
    expect(find.textContaining('not applied'), findsOneWidget);
    expect(find.text('+3 −1'), findsOneWidget);
    expect(find.text('bin'), findsOneWidget);
  });

  testWidgets('a plain diff has no message notice', (tester) async {
    await open(tester, _preview());
    expect(find.textContaining('not applied'), findsNothing);
  });

  testWidgets('defaults to the working tree; stage can be picked', (
    tester,
  ) async {
    await open(tester, _preview());
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(picked, PatchMode.worktree);

    await open(tester, _preview());
    await tester.tap(find.text('Apply and stage'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(picked, PatchMode.stage);
  });

  testWidgets('leaves out a mode the dry run ruled out', (tester) async {
    await open(tester, _preview(stage: false));
    expect(find.text('Apply to working tree'), findsOneWidget);
    expect(find.text('Apply and stage'), findsNothing);
  });

  testWidgets('a 3-way-only patch warns about conflicts', (tester) async {
    await open(
      tester,
      _preview(
        worktree: false,
        stage: false,
        threeWay: ThreeWayCheck.conflicts,
        error: 'error: f: patch does not apply',
      ),
    );
    expect(find.textContaining('conflicts'), findsWidgets);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(picked, PatchMode.threeWay);
  });

  testWidgets('nothing applies: shows git and disables Apply', (tester) async {
    await open(
      tester,
      _preview(
        worktree: false,
        stage: false,
        error: 'error: f: patch does not apply',
      ),
    );
    expect(find.text('error: f: patch does not apply'), findsOneWidget);
    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(apply.onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('fits narrow and wide windows', (tester) async {
    for (final w in [336.0, 480.0, 900.0]) {
      await open(
        tester,
        _preview(subjects: ['A subject long enough to need eliding ' * 3]),
        w: w,
      );
      expect(tester.takeException(), isNull, reason: 'at $w px');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  group('announcePatchOutcome', () {
    final l = lookupAppLocalizations(const Locale('en'));
    late ToastController toast;
    setUp(() => toast = ToastController());

    test('says whether the patch was staged', () {
      announcePatchOutcome(toast, l, PatchOutcome.applied, PatchMode.worktree);
      announcePatchOutcome(toast, l, PatchOutcome.applied, PatchMode.stage);
      expect(toast.state.map((t) => (t.title, t.kind)), [
        ('Patch applied', ToastKind.success),
        ('Patch applied and staged', ToastKind.success),
      ]);
    });

    test('a conflicted merge is a warning that says what to do', () {
      announcePatchOutcome(
        toast,
        l,
        PatchOutcome.conflicts,
        PatchMode.threeWay,
      );
      expect(toast.state.single.kind, ToastKind.warning);
      expect(toast.state.single.description, contains('Resolve'));
    });

    test('a failure adds nothing; the action already reported it', () {
      announcePatchOutcome(toast, l, PatchOutcome.failed, PatchMode.worktree);
      expect(toast.state, isEmpty);
    });
  });

  group('showApplyPatchFlow', () {
    late _NoGit git;
    late ProviderContainer c;

    Future<void> run(
      WidgetTester tester,
      Future<XFile?> Function() pick,
    ) async {
      git = _NoGit();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gitServiceProvider.overrideWithValue(git)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppTokens.dark()]),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showApplyPatchFlow(context, ref, '/r', pick: pick),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      c = ProviderScope.containerOf(tester.element(find.byType(Consumer)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('cancelling the picker does nothing', (tester) async {
      await run(tester, () async => null);
      expect(git.calls, 0);
      expect(c.read(toastProvider), isEmpty);
    });

    testWidgets('a file over the cap is refused before git sees it', (
      tester,
    ) async {
      await run(
        tester,
        () async =>
            XFile.fromData(Uint8List(20 * 1024 * 1024 + 1), name: 'huge.patch'),
      );
      expect(git.calls, 0);
      expect(c.read(toastProvider).single.title, 'Patch file is too large');
    });

    testWidgets('a file git finds no patch in is named in the toast', (
      tester,
    ) async {
      await run(
        tester,
        () async => XFile.fromData(
          Uint8List.fromList('hello\n'.codeUnits),
          name: 'notes.txt',
        ),
      );
      // The patch reaches git through a temp file, which only real async
      // time writes.
      for (var i = 0; i < 50 && c.read(toastProvider).isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final t = c.read(toastProvider).single;
      expect(t.title, 'Not a patch file');
      expect(t.description, contains('no git here'));
      expect(find.text('Apply'), findsNothing);
    });
  });
}
