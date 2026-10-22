// A repository's status is cached for as long as the app runs, and only the
// active tab is watched. Coming back to a tab, or to the app, has to re-read
// it: whatever changed meanwhile went unseen, and a repository with no remote
// has no background fetch to catch up for it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/repo_watcher.dart';
import 'package:mergelio/state/window_focus.dart';
import 'package:mergelio/state/workspace.dart';

import 'support/refresh_counter.dart';

void main() {
  late Map<String, int> refreshes;
  late WorkspaceController workspace;
  late ProviderContainer c;

  setUp(() {
    refreshes = {};
    // Paths that do not exist: the watcher sets up no disk watch for them,
    // so only the refreshes under test can happen.
    workspace = WorkspaceController()
      ..openRepo('/nowhere/a')
      ..openRepo('/nowhere/b')
      ..setActive(1);
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(SilentGit()),
        workspaceProvider.overrideWith((ref) => workspace),
        countRefreshes(refreshes),
      ],
    );
    // Both repositories have been shown before, so both have data cached.
    c.listen(repoDataProvider('/nowhere/a'), (_, _) {});
    c.listen(repoDataProvider('/nowhere/b'), (_, _) {});
    c.read(repoWatcherProvider);
  });
  tearDown(() => c.dispose());

  test('starting up reads nothing twice', () {
    expect(refreshes, isEmpty);
  });

  test('switching to a tab re-reads that repository', () {
    workspace.setActive(2);

    expect(refreshes, {'/nowhere/b': 1});
  });

  test('coming back to a tab re-reads it again', () {
    workspace
      ..setActive(2)
      ..setActive(1);

    expect(refreshes, {'/nowhere/b': 1, '/nowhere/a': 1});
  });

  test('closing the active tab re-reads the one shown next, then nothing', () {
    workspace
      ..closeTab(1)
      ..closeTab(2);

    expect(refreshes, {'/nowhere/b': 1});
  });

  test('the app regaining focus re-reads the active repository', () {
    c.read(windowFocusedProvider.notifier).state = false;
    expect(refreshes, isEmpty);

    c.read(windowFocusedProvider.notifier).state = true;

    expect(refreshes, {'/nowhere/a': 1});
  });

  test('refreshNow re-reads the active repository', () {
    c.read(repoWatcherProvider).refreshNow();

    expect(refreshes, {'/nowhere/a': 1});
  });

  test('with no repository open there is nothing to refresh', () {
    workspace
      ..closeTab(1)
      ..closeTab(2);
    refreshes.clear();

    c.read(repoWatcherProvider).refreshNow();
    c.read(windowFocusedProvider.notifier).state = false;
    c.read(windowFocusedProvider.notifier).state = true;

    expect(refreshes, isEmpty);
  });

  test('a repository opened for the first time is read once, not twice', () {
    workspace.openRepo('/nowhere/new');

    expect(refreshes, isEmpty);
  });
}
