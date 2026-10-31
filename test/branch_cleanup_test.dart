import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/maintenance.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/maintenance_panel.dart';

final _now = DateTime.utc(2026, 9, 30, 12);
int _secsAgo(int days) =>
    _now.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

/// Scripts the branch reads; nothing here spawns git.
class _FakeGit implements GitService {
  final calls = <String>[];
  final responses = <String, GitResult>{
    'for-each-ref --format=%(objectname) %(refname)': const GitResult(
      0,
      'a refs/heads/main\n',
      '',
    ),
    'for-each-ref --format=$branchInfoFormat refs/heads': GitResult(
      0,
      'main\t${_secsAgo(1)}\t\n'
          'done\t${_secsAgo(3)}\t\n'
          'also-done\t${_secsAgo(3)}\t\n'
          'held\t${_secsAgo(3)}\t\n'
          'old-work\t${_secsAgo(200)}\t\n',
      '',
    ),
    'symbolic-ref --quiet --short refs/remotes/origin/HEAD': const GitResult(
      0,
      'origin/main\n',
      '',
    ),
    'branch --show-current': const GitResult(0, 'main\n', ''),
    'for-each-ref --merged=main --format=%(refname:short) refs/heads':
        const GitResult(0, 'main\ndone\nalso-done\nheld\n', ''),
    'worktree list --porcelain': const GitResult(
      0,
      'worktree /r\nHEAD 1111\nbranch refs/heads/main\n\n'
          'worktree /wt/held\nHEAD 2222\nbranch refs/heads/held\n\n',
      '',
    ),
    'for-each-ref --format=%(refname)%09%(objectname) refs/heads':
        const GitResult(
          0,
          'refs/heads/done\tsha-done\nrefs/heads/also-done\tsha-also\n',
          '',
        ),
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final key = args.join(' ');
    calls.add(key);
    if (args.first == 'config') return const GitResult(1, '', '');
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

Future<void> _pump(WidgetTester tester, _FakeGit git, Widget home) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        maintenanceClockProvider.overrideWithValue(() => _now),
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(dateFormat: 'iso'),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _ticked(WidgetTester tester, String name) =>
    tester.widget<Checkbox>(find.byKey(ValueKey('mt-branch-$name'))).value ??
    false;

void main() {
  testWidgets('Select merged ticks merged branches no worktree holds', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(
      tester,
      git,
      const SingleChildScrollView(child: BranchCleanup(repoPath: '/r')),
    );

    await tester.tap(find.text('Select merged'));
    await tester.pump();

    expect(_ticked(tester, 'done'), isTrue);
    expect(_ticked(tester, 'also-done'), isTrue);
    expect(_ticked(tester, 'old-work'), isFalse);
    expect(_ticked(tester, 'held'), isFalse);

    await tester.tap(find.text('Delete 2 branches'));
    await tester.pumpAndSettle();
    // Nothing merged needs a force-delete warning.
    expect(find.textContaining('force-deleted'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(git.calls, containsAll(['branch -D done', 'branch -D also-done']));
    expect(git.calls.where((c) => c.contains('old-work')), isEmpty);
  });

  testWidgets('Select merged is off when nothing merged can go', (
    tester,
  ) async {
    final git = _FakeGit();
    git.responses['for-each-ref --merged=main --format=%(refname:short) '
        'refs/heads'] = const GitResult(
      0,
      'main\nheld\n',
      '',
    );
    await _pump(
      tester,
      git,
      const SingleChildScrollView(child: BranchCleanup(repoPath: '/r')),
    );

    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Select merged'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('showBranchCleanup opens the list in its own dialog', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeGit(),
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showBranchCleanup(context, '/r'),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Clean up branches'), findsOneWidget);
    expect(find.text('done'), findsOneWidget);
    // The rest of the maintenance panel is not part of it.
    expect(find.text('STORAGE'), findsNothing);
  });
}
