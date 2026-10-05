import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/edit_commit_message.dart';

/// Refuses each reword with [rejections] in turn, then lets it through.
class _FakeActions implements RepoActions {
  final List<HookRejectedException> rejections;
  final calls = <({String summary, bool noVerify})>[];
  _FakeActions(this.rejections);

  @override
  Future<List<String>> remoteBranchesContaining(String sha) async => const [];

  @override
  Future<HookRejectedException?> rewordCommit(
    String sha,
    String summary, {
    String description = '',
    bool noVerify = false,
  }) async {
    calls.add((summary: summary, noVerify: noVerify));
    return rejections.isEmpty ? null : rejections.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _commit = Commit(
  sha: 'abc',
  message: 'old',
  author: 'A',
  authorEmail: 'a@a',
  date: DateTime(2026),
);

Widget _harness(_FakeActions actions) => ProviderScope(
  overrides: [
    repoActionsProvider.overrideWith((ref, path) => actions),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: TextButton(
          onPressed: () =>
              editCommitMessage(context, ref, repoPath: '/r', commit: _commit),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _reword(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'new');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a hook refusing a reword shows its output and can be skipped', (
    tester,
  ) async {
    final actions = _FakeActions([
      HookRejectedException('commit-msg', const GitResult(1, '', 'no ticket')),
    ]);
    await tester.pumpWidget(_harness(actions));
    await _reword(tester);

    expect(
      find.text('The commit-msg hook rejected the commit'),
      findsOneWidget,
    );
    expect(find.text('no ticket'), findsOneWidget);
    // The edit dialog is gone, so nothing promises the message survived.
    expect(find.text('Your message was kept.'), findsNothing);
    expect(find.text('Skip hooks for next commit'), findsNothing);

    await tester.tap(find.text('Reword without hooks'));
    await tester.pumpAndSettle();
    expect(actions.calls, [
      (summary: 'new', noVerify: false),
      (summary: 'new', noVerify: true),
    ]);
    expect(find.text('The commit-msg hook rejected the commit'), findsNothing);
  });

  testWidgets('closing the dialog does not retry', (tester) async {
    final actions = _FakeActions([
      HookRejectedException('commit-msg', const GitResult(1, '', '')),
    ]);
    await tester.pumpWidget(_harness(actions));
    await _reword(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(actions.calls, hasLength(1));
  });

  testWidgets('no retry is offered for a hook --no-verify cannot skip', (
    tester,
  ) async {
    final actions = _FakeActions([
      HookRejectedException('prepare-commit-msg', const GitResult(1, '', '')),
    ]);
    await tester.pumpWidget(_harness(actions));
    await _reword(tester);
    expect(find.text('Reword without hooks'), findsNothing);
  });

  testWidgets('a hook that still refuses the retry is reported', (
    tester,
  ) async {
    final actions = _FakeActions([
      HookRejectedException('commit-msg', const GitResult(1, '', '')),
      HookRejectedException(
        'prepare-commit-msg',
        const GitResult(1, '', 'branch name'),
      ),
    ]);
    await tester.pumpWidget(_harness(actions));
    await _reword(tester);
    await tester.tap(find.text('Reword without hooks'));
    await tester.pumpAndSettle();
    expect(
      find.text('The prepare-commit-msg hook rejected the commit'),
      findsOneWidget,
    );
    expect(find.text('branch name'), findsOneWidget);
  });
}
