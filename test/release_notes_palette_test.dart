import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/release_notes.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:pub_semver/pub_semver.dart';

/// A git service that answers every command with success and no output, so
/// nothing reads the host repository or spawns a real git process.
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

void main() {
  final v19 = Version.parse('1.9.0');
  final v110 = Version.parse('1.10.0');

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Future<Version> Function() current,
    List<Override> extraOverrides = const [],
  }) async {
    final c = ProviderContainer(
      overrides: [
        currentReleaseProvider.overrideWith((ref) => current()),
        ...extraOverrides,
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => openGlobalPalette(context, ref),
                child: const Text('palette'),
              ),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  testWidgets('dashboard palette offers What\'s new', (t) async {
    final c = await pump(t, current: () async => v19);
    final ctl = c.read(workspaceProvider.notifier);
    ctl.openRepo('/r/a');
    ctl.showDashboard();
    await t.tap(find.text('palette'));
    await t.pumpAndSettle();
    await t.tap(find.text("What's new"));
    await t.pumpAndSettle();
    expect(c.read(workspaceProvider).releaseNotes, [v19]);
    expect(c.read(workspaceProvider).showReleaseNotes, isTrue);
  });

  testWidgets('repo palette offers What\'s new', (t) async {
    const repoPath = '/r/a';
    final c = await pump(
      t,
      current: () async => v19,
      extraOverrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        repoDataProvider(repoPath)
            .overrideWith((ref) async => const RepoData()),
      ],
    );
    final ctl = c.read(workspaceProvider.notifier);
    ctl.openRepo(repoPath);
    await t.tap(find.text('palette'));
    await t.pumpAndSettle();
    // The repo list runs past the test viewport, and the palette builds rows
    // lazily, so the search field narrows it to the entry under test.
    await t.enterText(find.byType(TextField), "What's new");
    await t.pumpAndSettle();
    // The search field echoes the query, so the tap targets the list row only.
    await t.tap(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text("What's new"),
      ),
    );
    await t.pumpAndSettle();
    expect(c.read(workspaceProvider).releaseNotes, [v19]);
    expect(c.read(workspaceProvider).showReleaseNotes, isTrue);
  });

  testWidgets('reopening keeps the versions the launch tab showed', (t) async {
    final c = await pump(t, current: () async => v110);
    final ctl = c.read(workspaceProvider.notifier);
    ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v110, v19]);
    ctl.showDashboard();
    await t.tap(find.text('palette'));
    await t.pumpAndSettle();
    await t.tap(find.text("What's new"));
    await t.pumpAndSettle();
    expect(c.read(workspaceProvider).releaseNotes, [v110, v19]);
  });

  testWidgets('an unknown running version opens nothing', (t) async {
    final c = await pump(
      t,
      current: () async => throw StateError('no package info'),
    );
    final ctl = c.read(workspaceProvider.notifier);
    ctl.openRepo('/r/a');
    ctl.showDashboard();
    await t.tap(find.text('palette'));
    await t.pumpAndSettle();
    await t.tap(find.text("What's new"));
    await t.pumpAndSettle();
    expect(c.read(workspaceProvider).releaseNotes, isNull);
  });
}
