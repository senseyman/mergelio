import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

const _repoPath = '/home/u/repo';

/// Records every argv. Reports an upstream and a branch name, so the push
/// argument building has something realistic to work from.
class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    if (args.first == 'rev-parse' && args.last == 'HEAD') {
      return const GitResult(0, 'main\n', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

List<List<String>> _pushCalls(_FakeGit git) =>
    git.calls.where((c) => c.first == 'push').toList();

Future<_FakeGit> _openDialog(WidgetTester tester, List<String> remotes) async {
  final git = _FakeGit();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        repoDataProvider(_repoPath)
            .overrideWith((ref) async => RepoData(remotes: remotes)),
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
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showPushDialog(context, ref, _repoPath),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return git;
}

void main() {
  testWidgets('a repository with no remotes says so instead of offering an '
      'empty picker', (tester) async {
    final git = await _openDialog(tester, const []);

    expect(
      find.text('This repository has no remotes. Add one before pushing.'),
      findsOneWidget,
    );
    expect(_pushCalls(git), isEmpty);
  });

  testWidgets('pushes to the picked remote and carries the tags option', (
    tester,
  ) async {
    final git = await _openDialog(tester, const ['origin', 'mirror']);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mirror').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Also push all tags'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Push'));
    await tester.pumpAndSettle();

    expect(_pushCalls(git), [
      ['push', 'mirror', 'main', '--tags'],
    ]);
  });

  testWidgets('cancelling pushes nothing', (tester) async {
    final git = await _openDialog(tester, const ['origin']);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(_pushCalls(git), isEmpty);
  });
}
