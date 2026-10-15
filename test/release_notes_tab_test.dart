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
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_status_bar.dart';
import 'package:mergelio/ui/shell/app_tab_bar.dart';
import 'package:pub_semver/pub_semver.dart';

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
  late ProviderContainer c;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 400),
    bool statusBar = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(groupStyle: 'dropdown'),
          ),
        ),
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
            body: Column(
              children: [
                const AppTabBar(),
                const Spacer(),
                if (statusBar) const AppStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  WorkspaceController ctl() => c.read(workspaceProvider.notifier);

  testWidgets('notes tab shows, titles the status bar, closes', (t) async {
    await pump(t);
    ctl().openRepo('/r/a');
    ctl().openReleaseNotes([v19]);
    await t.pump();
    // Tab label and status bar title.
    expect(find.text("What's new"), findsNWidgets(2));

    await t.tap(find.byTooltip('Close release notes'));
    await t.pump();
    expect(find.text("What's new"), findsNothing);
    expect(c.read(workspaceProvider).releaseNotes, isNull);
  });

  testWidgets('stays visible under a group filter', (t) async {
    await pump(t);
    ctl().openRepo('/r/a');
    ctl().setActiveGroup(ctl().createGroup('Work').id);
    ctl().openReleaseNotes([v19]);
    await t.pump();
    expect(find.text("What's new"), findsWidgets);
  });

  testWidgets('tapping the repo tab, then the notes tab, switches', (t) async {
    await pump(t);
    ctl().openRepo('/r/a');
    ctl().openReleaseNotes([v19]);
    await t.pump();

    await t.tap(find.text('a'));
    await t.pump();
    expect(c.read(workspaceProvider).showReleaseNotes, isFalse);

    await t.tap(find.text("What's new"));
    await t.pump();
    expect(c.read(workspaceProvider).showReleaseNotes, isTrue);
  });

  for (final w in [336.0, 800.0]) {
    testWidgets('tab strip scrolls rather than overflows at ${w}px', (t) async {
      // The status bar has its own fixed-width content; this sweep is about
      // the tab strip.
      await pump(t, size: Size(w, 400), statusBar: false);
      ctl().openRepo('/r/a');
      ctl().openRepo('/r/b');
      ctl().openRepo('/r/c');
      ctl().openReleaseNotes([v19]);
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
