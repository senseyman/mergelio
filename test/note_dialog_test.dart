import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/edit_note.dart';

/// Answers `notes show` with [note] (or [showExit]) and records every call
/// with what it was fed.
class _NotesGit implements GitService {
  final String note;
  final int showExit;
  final calls = <(List<String>, String?)>[];
  _NotesGit({this.note = '', this.showExit = 0});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add((args, stdin));
    if (args.length > 1 && args[0] == 'notes' && args[1] == 'show') {
      return showExit == 0
          ? GitResult(0, '$note\n', '')
          : GitResult(showExit, '', 'fatal: bad object deadbeef');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late String? result;
  late bool closed;

  Future<void> open(WidgetTester tester, {String initial = ''}) async {
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showNoteDialog(context, initial: initial);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a commit without a note gets an add dialog', (tester) async {
    await open(tester);
    expect(find.text('Add note'), findsOneWidget);
    // Notes are not carried by an ordinary push; the dialog says so.
    expect(find.textContaining('push them'), findsOneWidget);
  });

  testWidgets('an existing note is prefilled and saved as edited', (
    tester,
  ) async {
    await open(tester, initial: 'old text');
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('old text'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'line one\n\nline three');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, 'line one\n\nline three');
  });

  testWidgets('saving an emptied note returns its text, not a cancel', (
    tester,
  ) async {
    await open(tester, initial: 'old text');
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, '  ');
  });

  testWidgets('the leading indent of a note survives the dialog', (
    tester,
  ) async {
    await open(tester, initial: 'old');
    await tester.enterText(find.byType(TextField), '    code');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, '    code');
  });

  testWidgets('cancel returns null', (tester) async {
    await open(tester, initial: 'old text');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  group('editCommitNote', () {
    Future<ProviderContainer> start(WidgetTester tester, _NotesGit git) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gitServiceProvider.overrideWithValue(git)],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => editCommitNote(
                    context,
                    ref,
                    repoPath: '/r',
                    sha: 'abc1234def',
                  ),
                  child: const Text('edit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.text('edit')));
    }

    testWidgets('opens on the note git has and writes the edit', (
      tester,
    ) async {
      final git = _NotesGit(note: 'from git');
      await start(tester, git);
      expect(find.text('Edit note'), findsOneWidget);
      expect(find.text('from git'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'edited');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final write = git.calls.where((c) => c.$1.contains('add')).single;
      expect(write.$1.sublist(write.$1.indexOf('notes')), [
        'notes',
        'add',
        '-f',
        '-F',
        '-',
        'abc1234def',
      ]);
      expect(write.$2, 'edited');
    });

    testWidgets('a note git cannot read opens no editor', (tester) async {
      final git = _NotesGit(showExit: 128);
      final c = await start(tester, git);
      expect(find.byType(TextField), findsNothing);
      final t = c.read(toastProvider).single;
      expect(t.title, 'Could not read the note');
      expect(t.description, contains('bad object'));
    });
  });
}
