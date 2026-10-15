import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/recents.dart';
import 'package:mergelio/state/release_notes.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/release_notes/release_notes_view.dart';
import 'package:mergelio/ui/shell/app_shell.dart';
import 'package:mergelio/state/update_controller.dart';
import 'package:pub_semver/pub_semver.dart';

import 'helpers/update_fakes.dart';

class _MemoryRecents implements RecentsRepository {
  @override
  AppDatabase get db => throw UnimplementedError();
  @override
  Future<List<RecentRepo>> load() async => const [];
  @override
  Future<void> save(List<RecentRepo> items) async {}
}

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  final v19 = Version.parse('1.9.0');

  Future<(ProviderContainer, int Function())> pump(
    WidgetTester tester,
    List<Version> launch,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var runs = 0;
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            const ProfilesState(
              profiles: [
                Profile(
                  id: 'p',
                  label: 'Work',
                  name: 'N',
                  email: 'n@x.io',
                  colorValue: 0xFF336699,
                ),
              ],
              activeId: 'p',
            ),
          ),
        ),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(updateConsent: 'off'),
          ),
        ),
        updateStatusProvider.overrideWith(
          (ref) => fakeUpdateController(const UpdateIdle()),
        ),
        recentsProvider.overrideWith(
          (ref) => RecentsController(_MemoryRecents(), const []),
        ),
        releaseNotesLaunchProvider.overrideWith((ref) async {
          runs++;
          return launch;
        }),
        releaseNotesAssetsProvider.overrideWith(
          (ref) async => {
            v19: {'en'},
          },
        ),
        releaseNotesTextProvider.overrideWith((ref, key) async => 'body'),
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
          home: const AppShell(),
        ),
      ),
    );
    // Post-frame callback, then the launch future and the state change.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return (c, () => runs);
  }

  testWidgets('shows the notes tab once on launch, with no repo open', (
    t,
  ) async {
    final (c, runs) = await pump(t, [v19]);
    final ws = c.read(workspaceProvider);
    expect(ws.releaseNotes, [v19]);
    expect(ws.showReleaseNotes, isTrue);
    expect(ws.hasRepo, isFalse);
    expect(find.byType(ReleaseNotesView), findsOneWidget);
    expect(runs(), 1);

    // Rebuilding the shell must not run the launch decision again.
    c.read(settingsProvider.notifier).setAutoFetch(false);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(runs(), 1);
  });

  testWidgets('leaves the workspace alone when the launch has no notes', (
    t,
  ) async {
    final (c, runs) = await pump(t, const []);
    expect(c.read(workspaceProvider).releaseNotes, isNull);
    expect(find.byType(ReleaseNotesView), findsNothing);
    expect(runs(), 1);
  });
}
