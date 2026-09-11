import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

/// A repository on `main` with one other local branch, `feature`.
class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    final out = switch (args.first) {
      'remote' when args.length == 1 => '',
      'for-each-ref' when args.contains('refs/heads') =>
        args.any((a) => a.contains('%(HEAD)'))
            ? 'main\t*\t\tsha1\t\nfeature\t\t\tsha2\t\n'
            : 'main\nfeature\n',
      'rev-parse' => 'deadbeef\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;

  List<String> get mergeCall => calls.firstWhere((c) => c.contains('merge'));
}

void main() {
  Future<_FakeGit> openDialog(WidgetTester tester) async {
    final git = _FakeGit();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showMergeDialog(context, ref, '/r'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature').last);
    await tester.pumpAndSettle();
    return git;
  }

  testWidgets('a plain merge still passes --no-ff and nothing else', (
    tester,
  ) async {
    final git = await openDialog(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(git.mergeCall, contains('--no-ff'));
    expect(git.mergeCall, isNot(contains('--squash')));
    expect(git.mergeCall, isNot(contains('-X')));
  });

  testWidgets('squash is offered and reaches git', (tester) async {
    final git = await openDialog(tester);
    await tester.tap(find.text('Squash (stage, do not commit)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(git.mergeCall, contains('--squash'));
  });

  testWidgets('stage-without-committing is offered and reaches git', (
    tester,
  ) async {
    final git = await openDialog(tester);
    await tester.tap(find.text('Stage the merge, do not commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(git.mergeCall, contains('--no-commit'));
  });

  testWidgets('favouring a side passes -X', (tester) async {
    final git = await openDialog(tester);
    await tester.tap(find.text('Theirs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(git.mergeCall, containsAllInOrder(['-X', 'theirs']));
  });

  testWidgets('turning squash on clears the stage-only choice it overrides', (
    tester,
  ) async {
    final git = await openDialog(tester);
    await tester.tap(find.text('Stage the merge, do not commit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squash (stage, do not commit)'));
    await tester.pumpAndSettle();
    // Back out of squash: the choice it disabled must not come back checked.
    await tester.tap(find.text('Squash (stage, do not commit)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(git.mergeCall, isNot(contains('--no-commit')));
    expect(git.mergeCall, isNot(contains('--squash')));
  });
}
