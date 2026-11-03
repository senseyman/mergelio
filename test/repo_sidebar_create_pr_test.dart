import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

const _github = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

const _gitlab = ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'gitlab.com',
  owner: 'g',
  repo: 'r',
);

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => GitResult(0, args.first == 'rev-parse' ? 'deadbeef\n' : '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _data = RepoData(
  branches: [
    Branch(name: 'main', current: true, upstream: 'origin/main'),
    Branch(name: 'feature/x', upstream: 'origin/feature/x'),
    Branch(name: 'local-only'),
    Branch(name: 'forked', upstream: 'fork/forked'),
    // Still names its upstream, but the remote branch is gone — deleted after
    // its pull request merged, say.
    Branch(name: 'merged', upstream: 'origin/merged'),
    Branch(name: 'renamed', upstream: 'origin/published'),
    // Pushed without -u, so git recorded no upstream.
    Branch(name: 'no-link'),
  ],
  remotes: ['origin', 'fork'],
  remoteBranches: [
    RemoteBranch(remote: 'origin', branch: 'main'),
    RemoteBranch(remote: 'origin', branch: 'feature/x'),
    RemoteBranch(remote: 'origin', branch: 'topic'),
    RemoteBranch(remote: 'origin', branch: 'published'),
    RemoteBranch(remote: 'origin', branch: 'no-link'),
    RemoteBranch(remote: 'fork', branch: 'elsewhere'),
  ],
);

class _Harness {
  final List<Uri> opened;
  final ProviderContainer container;
  _Harness(this.opened, this.container);
  List<Toast> get toasts => container.read(toastProvider);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required ForgeHost? host,
  bool launchSucceeds = true,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        worktreeByBranchProvider('/r').overrideWithValue(const {}),
        repoDataProvider('/r').overrideWith((ref) async => _data),
        forgeHostProvider.overrideWith((ref, path) async => host),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        pullRequestPanelProvider.overrideWith(
          (ref, path) async => const ForgePanel(),
        ),
        issuePanelProvider.overrideWith((ref, path) async => const []),
        forgeLaunchUrlProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return launchSucceeds;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: RepoSidebar(onCollapse: () {})),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RepoSidebar)),
  );
  container.read(workspaceProvider.notifier).openRepo('/r');
  await tester.pumpAndSettle();
  return _Harness(opened, container);
}

/// Opens the context menu of the row labelled [label] and checks it is the
/// menu the test means: a local branch's menu has "Set upstream…", a remote
/// branch's does not. A local branch and its origin copy can share a label,
/// so the label alone does not say which row was hit.
Future<void> _menuOn(
  WidgetTester tester,
  String label, {
  bool local = true,
}) async {
  final rows = find.text(label);
  // The Branches section is drawn above Remotes, so the first match is the
  // local row and the last the remote one.
  await tester.tap(local ? rows.first : rows.last, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  expect(find.text('Set upstream…'), local ? findsOneWidget : findsNothing);
}

void main() {
  testWidgets('a pushed branch opens the github compare page', (tester) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'x');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, [
      Uri.parse('https://github.com/o/r/compare/feature/x?expand=1'),
    ]);
    expect(h.toasts, isEmpty);
  });

  testWidgets('a gitlab repository offers a merge request instead', (
    tester,
  ) async {
    final h = await _pump(tester, host: _gitlab);

    await _menuOn(tester, 'x');
    expect(find.text('Create pull request…'), findsNothing);
    await tester.tap(find.text('Create merge request…'));
    await tester.pumpAndSettle();

    expect(h.opened.single.path, '/g/r/-/merge_requests/new');
    expect(
      h.opened.single.queryParameters['merge_request[source_branch]'],
      'feature/x',
    );
  });

  testWidgets('a repository off any forge has no such entry', (tester) async {
    await _pump(tester, host: null);

    await _menuOn(tester, 'x');

    expect(find.text('Create pull request…'), findsNothing);
    expect(find.text('Create merge request…'), findsNothing);
  });

  testWidgets('an unpushed branch says to push first and opens nothing', (
    tester,
  ) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'local-only');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, isEmpty);
    expect(h.toasts.single.kind, ToastKind.info);
    expect(h.toasts.single.title, contains('local-only'));
  });

  testWidgets('a branch tracking another remote also says to push first', (
    tester,
  ) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'forked');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, isEmpty);
    expect(h.toasts.single.title, contains('forked'));
  });

  testWidgets('a branch whose upstream is gone says to push first', (
    tester,
  ) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'merged');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, isEmpty);
    expect(h.toasts.single.title, contains('merged'));
  });

  testWidgets('a local branch proposes the name its upstream has on origin', (
    tester,
  ) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'renamed');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, [
      Uri.parse('https://github.com/o/r/compare/published?expand=1'),
    ]);
  });

  testWidgets('a branch pushed without an upstream still opens its page', (
    tester,
  ) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'no-link');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, [
      Uri.parse('https://github.com/o/r/compare/no-link?expand=1'),
    ]);
    expect(h.toasts, isEmpty);
  });

  testWidgets('a browser that will not open is reported', (tester) async {
    final h = await _pump(tester, host: _github, launchSucceeds: false);

    await _menuOn(tester, 'x');
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, hasLength(1));
    expect(h.toasts.single.kind, ToastKind.error);
  });

  testWidgets('an origin remote branch opens its compare page', (tester) async {
    final h = await _pump(tester, host: _github);

    await _menuOn(tester, 'topic', local: false);
    await tester.tap(find.text('Create pull request…'));
    await tester.pumpAndSettle();

    expect(h.opened, [
      Uri.parse('https://github.com/o/r/compare/topic?expand=1'),
    ]);
  });

  testWidgets('a remote branch on another remote has no such entry', (
    tester,
  ) async {
    await _pump(tester, host: _github);

    await _menuOn(tester, 'elsewhere', local: false);

    expect(find.text('Create pull request…'), findsNothing);
  });
}
