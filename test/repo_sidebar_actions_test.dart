import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/state/branch_filter.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/state/worktrees.dart';
import 'package:mergelio/ui/workspace/branch_cleanup.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

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
    final out = switch (args.first) {
      'for-each-ref' when args.contains('refs/heads') =>
        'main\t*\t\nfeature\t\t\n',
      'rev-parse' => 'deadbeef\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Pumps [RepoSidebar] with the active repo open, optionally with
/// `worktreeByBranchProvider('/r')` overridden so a branch appears held by
/// another worktree.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeGit git, {
  Map<String, Worktree> heldBy = const {},
  RepoData? data,
}) async {
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
        worktreeByBranchProvider('/r').overrideWithValue(heldBy),
        if (data != null)
          repoDataProvider('/r').overrideWith((ref) async => data),
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
  return container;
}

void main() {
  group('branch filter', () {
    const data = RepoData(
      branches: [
        Branch(name: 'main', current: true),
        Branch(name: 'feat/login-form'),
        Branch(name: 'feat/signup'),
        Branch(name: 'fix/crash'),
      ],
    );
    Finder field() => find.byKey(const ValueKey('sb-branch-filter'));
    Size header(WidgetTester tester, Finder inside) => tester.getSize(
      find.ancestor(of: inside, matching: find.byType(Padding)).at(0),
    );

    Future<void> openFilter(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Filter branches'));
      await tester.pumpAndSettle();
    }

    testWidgets('the box opens from the header icon, in the header row', (
      tester,
    ) async {
      await _pump(tester, _FakeGit(), data: data);
      expect(field(), findsNothing);

      await openFilter(tester);

      expect(field(), findsOneWidget);
      // It takes the label's place rather than adding a row.
      expect(find.text('BRANCHES'), findsNothing);
      expect(
        tester.getRect(field()).center.dy,
        lessThan(tester.getRect(find.text('feat')).top),
      );
      // Focused, so typing goes straight in.
      final editable = tester.widget<EditableText>(
        find.descendant(of: field(), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      // No taller than another section's header.
      expect(
        header(tester, field()).height,
        header(tester, find.text('REMOTES')).height,
      );
    });

    testWidgets('opening it on a collapsed section opens the section', (
      tester,
    ) async {
      final c = await _pump(tester, _FakeGit(), data: data);
      c.read(settingsProvider.notifier).toggleSection('branches');
      await tester.pumpAndSettle();
      expect(find.text('signup'), findsNothing);

      await openFilter(tester);

      expect(find.text('signup'), findsOneWidget);
    });

    testWidgets('narrows the list, even inside a collapsed folder', (
      tester,
    ) async {
      final c = await _pump(tester, _FakeGit(), data: data);
      c.read(settingsProvider.notifier).toggleSection('branchdir:feat');
      await tester.pumpAndSettle();
      expect(find.text('login-form'), findsNothing);

      await openFilter(tester);
      await tester.enterText(field(), 'login');
      await tester.pumpAndSettle();

      expect(find.text('login-form'), findsOneWidget);
      expect(find.text('signup'), findsNothing);
      expect(find.text('crash'), findsNothing);
      expect(find.text('main'), findsNothing);
    });

    testWidgets('says when nothing matches; Esc clears and closes the box', (
      tester,
    ) async {
      await _pump(tester, _FakeGit(), data: data);
      await openFilter(tester);

      await tester.enterText(field(), 'nope');
      await tester.pumpAndSettle();
      expect(find.text('No matching branches'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field(), findsNothing);
      expect(find.text('BRANCHES'), findsOneWidget);
      expect(find.text('No matching branches'), findsNothing);
      expect(find.text('signup'), findsOneWidget);

      // Reopened, it starts empty.
      await openFilter(tester);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    });

    testWidgets('the clear button empties the query and keeps the box', (
      tester,
    ) async {
      await _pump(tester, _FakeGit(), data: data);
      await openFilter(tester);
      await tester.enterText(field(), 'signup');
      await tester.pumpAndSettle();
      expect(find.text('crash'), findsNothing);

      await tester.tap(find.byTooltip('Clear filter'));
      await tester.pumpAndSettle();
      expect(find.text('crash'), findsOneWidget);
      expect(field(), findsOneWidget);
    });

    testWidgets('a repo without branches offers no filter', (tester) async {
      await _pump(tester, _FakeGit(), data: const RepoData());
      expect(find.byTooltip('Filter branches'), findsNothing);
    });

    testWidgets('removing the open box from the tree reports nothing', (
      tester,
    ) async {
      await _pump(tester, _FakeGit(), data: data);
      await openFilter(tester);

      // The sidebar going away (collapsed, or the window's layout changing)
      // takes the focused box with it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('switching repos leaves each repo its own filter', (
      tester,
    ) async {
      final c = await _pump(tester, _FakeGit(), data: data);
      await openFilter(tester);
      await tester.enterText(field(), 'signup');
      await tester.pumpAndSettle();

      c.read(workspaceProvider.notifier).openRepo('/other');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(field(), findsNothing);
      expect(c.read(branchFilterProvider('/r')), 'signup');

      c.read(workspaceProvider.notifier).openRepo('/r');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field()).controller!.text, 'signup');
      expect(find.text('crash'), findsNothing);
    });

    testWidgets('an empty box closes when focus leaves it', (tester) async {
      await _pump(tester, _FakeGit(), data: data);
      await openFilter(tester);

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(field(), findsNothing);
    });
  });

  testWidgets('the Branches menu keeps its header as tall as the others', (
    tester,
  ) async {
    await _pump(tester, _FakeGit());
    Size header(String label) => tester.getSize(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );
    expect(header('BRANCHES').height, header('REMOTES').height);
  });

  testWidgets('the Branches menu opens branch clean-up', (tester) async {
    await _pump(tester, _FakeGit());

    await tester.tap(find.byKey(const ValueKey('sb-branches-menu')));
    await tester.pumpAndSettle();
    // Sizing the button must not size the menu along with it.
    expect(
      tester
          .getSize(
            find.widgetWithText(PopupMenuItem<void>, 'Clean up branches…'),
          )
          .width,
      greaterThan(100),
    );
    await tester.tap(find.text('Clean up branches…'));
    await tester.pumpAndSettle();

    expect(find.text('Clean up branches'), findsOneWidget);
    final list = tester.widget<BranchCleanup>(find.byType(BranchCleanup));
    expect(list.repoPath, '/r');
    // This repo's only other branch is neither merged nor stale.
    expect(find.text('No merged or stale branches.'), findsOneWidget);
  });

  testWidgets('double-clicking a branch checks it out', (tester) async {
    final git = _FakeGit();
    await _pump(tester, git);

    // The non-current branch is checkout-able via double-tap.
    final gesture = find.text('feature');
    expect(gesture, findsOneWidget);
    await tester.tap(gesture);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(gesture);
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.first == 'checkout' && c.contains('feature')),
      isTrue,
    );
  });

  testWidgets('dragging a branch onto another opens the merge/rebase menu', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('feature')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('main')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('Merge «feature» into «main»'), findsOneWidget);
    expect(find.textContaining('Rebase «feature» onto «main»'), findsOneWidget);
  });

  group('branches held by another worktree consult the collision guard', () {
    testWidgets('double-tap shows the dialog instead of checking out', (
      tester,
    ) async {
      final git = _FakeGit();
      await _pump(
        tester,
        git,
        heldBy: {'feature': const Worktree(path: '/other', branch: 'feature')},
      );

      final gesture = find.text('feature');
      await tester.tap(gesture);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(gesture);
      await tester.pumpAndSettle();

      expect(find.text('Checkout anyway'), findsOneWidget);
      expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
    });

    testWidgets(
      'the context-menu Checkout item shows the dialog instead of checking out',
      (tester) async {
        final git = _FakeGit();
        await _pump(
          tester,
          git,
          heldBy: {
            'feature': const Worktree(path: '/other', branch: 'feature'),
          },
        );

        await tester.tapAt(
          tester.getCenter(find.text('feature')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Checkout'));
        await tester.pumpAndSettle();

        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
      },
    );

    testWidgets(
      'the remote-branch menu switch item shows the dialog instead of '
      'checking out',
      (tester) async {
        final git = _FakeGit();
        await _pump(
          tester,
          git,
          heldBy: {
            'feature': const Worktree(path: '/other', branch: 'feature'),
          },
          // A remote branch whose local counterpart exists: switching to it
          // checks out that local branch, which another worktree holds.
          data: const RepoData(
            branches: [Branch(name: 'main', current: true)],
            remotes: ['origin'],
            remoteBranches: [
              RemoteBranch(remote: 'origin', branch: 'feature', hasLocal: true),
            ],
          ),
        );

        await tester.tapAt(
          tester.getCenter(find.text('feature')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch to feature'));
        await tester.pumpAndSettle();

        expect(find.text('Checkout anyway'), findsOneWidget);
        expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
      },
    );
  });
}
