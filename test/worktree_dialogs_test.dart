import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/worktree.dart';
import 'package:mergelio/ui/workspace/worktree_dialogs.dart';

const _existing = [
  Worktree(path: '/home/u/repo', branch: 'main', kind: WorktreeKind.main),
  Worktree(path: '/home/u/repo-login', branch: 'feat/login'),
];

/// Never touches the real filesystem — tests that care about the "not empty"
/// branch pass their own [isNonEmptyDir].
bool _noRealDirs(String path) => false;

/// Holds the dialog's eventual result. `showAddWorktreeDialog`'s future only
/// resolves once the dialog is dismissed, well after [_open] returns, so the
/// value has to be read through a mutable box rather than a return value.
class _Result {
  AddWorktreeData? value;
}

Future<_Result> _open(
  WidgetTester tester, {
  bool Function(String path) isNonEmptyDir = _noRealDirs,
  bool hasSubmodules = false,
}) async {
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: [AppTokens.dark()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result.value = await showAddWorktreeDialog(
                context,
                repoPath: '/home/u/repo',
                existing: _existing,
                branches: const ['main', 'feat/login', 'hotfix'],
                currentBranch: 'main',
                isNonEmptyDir: isNonEmptyDir,
                hasSubmodules: hasSubmodules,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// The dialog's platform-dependent widgets (e.g. the directory picker button)
/// only matter on desktop, and widget tests default to Android. The override
/// has to be undone inside the test body — the framework checks it before the
/// top-level tearDown runs.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('prefills a sibling path once a branch name is typed', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/x',
      );
      await tester.pump();
      expect(
        find.widgetWithText(TextField, '/home/u/repo-feat-x'),
        findsOneWidget,
      );
    });
  });

  testWidgets('rejects a destination inside the repository', (tester) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-path')),
        '/home/u/repo/inside',
      );
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'ok',
      );
      await tester.pump();
      expect(
        find.text('Choose a location outside the repository'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the existing-branch dropdown shows its pre-selection', (
    tester,
  ) async {
    // A closed dropdown renders its selected item and nothing else, so the
    // branch name being on screen before any interaction is what proves the
    // pre-selection reached the button rather than only the form field.
    // 'hotfix' is the first branch no other worktree holds.
    await _onDesktop(() async {
      await _open(tester);
      expect(find.text('hotfix'), findsOneWidget);
      await tester.tap(find.byKey(const Key('worktree-mode-existing')));
      await tester.pumpAndSettle();
      expect(find.text('hotfix'), findsOneWidget);
    });
  });

  testWidgets('rejects a new branch name that already exists', (tester) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'hotfix',
      );
      await tester.pump();
      expect(find.text('That branch already exists'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Add worktree'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  testWidgets('an empty start point is reported as none, not as ""', (
    tester,
  ) async {
    // '' would reach git as an argument of its own — "invalid reference: ''"
    // — where leaving it out lets git default to HEAD, which is what an empty
    // field means.
    await _onDesktop(() async {
      final result = await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/x',
      );
      await tester.enterText(find.byKey(const Key('worktree-start-point')), '');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add worktree'));
      await tester.pumpAndSettle();
      expect(result.value, isNotNull);
      expect(result.value!.startPoint, isNull);
    });
  });

  testWidgets('warns that submodules are left uninitialised', (tester) async {
    await _onDesktop(() async {
      await _open(tester, hasSubmodules: true);
      expect(
        find.textContaining('Submodules are not checked out'),
        findsOneWidget,
      );
    });
  });

  testWidgets('says nothing about submodules when there are none', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _open(tester);
      expect(find.textContaining('Submodules'), findsNothing);
    });
  });

  testWidgets('rejects an illegal branch name', (tester) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'has space',
      );
      await tester.pump();
      expect(
        find.text('Branch names cannot contain spaces or ~ ^ : ? * [ \\'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a branch held by another worktree cannot be attached', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('worktree-mode-existing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('worktree-existing-branch')));
      await tester.pumpAndSettle();
      // 'feat/login' is held by /home/u/repo-login and must be disabled.
      final item = tester.widget<DropdownMenuItem<String>>(
        find.widgetWithText(DropdownMenuItem<String>, 'feat/login').last,
      );
      expect(item.enabled, isFalse);
    });
  });

  testWidgets('returns the entered values for a new branch', (tester) async {
    await _onDesktop(() async {
      final result = await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/x',
      );
      await tester.enterText(
        find.byKey(const Key('worktree-start-point')),
        'develop',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add worktree'));
      await tester.pumpAndSettle();
      // The dialog is gone; its result was delivered to the caller.
      expect(find.byKey(const Key('worktree-path')), findsNothing);
      expect(result.value, isNotNull);
      expect(result.value!.path, '/home/u/repo-feat-x');
      expect(result.value!.newBranch, 'feat/x');
      expect(result.value!.startPoint, 'develop');
      expect(result.value!.existingBranch, isNull);
      expect(result.value!.detach, isFalse);
      expect(result.value!.openTab, isTrue);
    });
  });

  testWidgets('returns the entered values for an existing branch', (
    tester,
  ) async {
    await _onDesktop(() async {
      final result = await _open(tester);
      await tester.tap(find.byKey(const Key('worktree-mode-existing')));
      await tester.pumpAndSettle();
      // 'hotfix' is the only branch not already held, so it is already the
      // dropdown's default selection — opening it fires no onChanged, and
      // the path is never auto-derived for this mode. Set it by hand.
      await tester.enterText(
        find.byKey(const Key('worktree-path')),
        '/home/u/repo-hotfix',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add worktree'));
      await tester.pumpAndSettle();
      expect(result.value, isNotNull);
      expect(result.value!.path, '/home/u/repo-hotfix');
      expect(result.value!.newBranch, isNull);
      expect(result.value!.startPoint, isNull);
      expect(result.value!.existingBranch, 'hotfix');
      expect(result.value!.detach, isFalse);
    });
  });

  testWidgets('returns the entered values when detached', (tester) async {
    await _onDesktop(() async {
      final result = await _open(tester);
      await tester.tap(find.byKey(const Key('worktree-mode-detached')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('worktree-path')),
        '/home/u/repo-scratch',
      );
      await tester.enterText(
        find.byKey(const Key('worktree-start-point')),
        'v1.0.0',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add worktree'));
      await tester.pumpAndSettle();
      expect(result.value, isNotNull);
      expect(result.value!.path, '/home/u/repo-scratch');
      expect(result.value!.newBranch, isNull);
      expect(result.value!.existingBranch, isNull);
      expect(result.value!.startPoint, 'v1.0.0');
      expect(result.value!.detach, isTrue);
    });
  });

  testWidgets('unchecking "open in a new tab" is reflected in the result', (
    tester,
  ) async {
    await _onDesktop(() async {
      final result = await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/x',
      );
      await tester.pump();
      await tester.tap(find.text('Open in a new tab'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add worktree'));
      await tester.pumpAndSettle();
      expect(result.value!.openTab, isFalse);
    });
  });

  testWidgets('stops deriving the path once the user edits it by hand', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/x',
      );
      await tester.pump();
      // Hand-edit the path away from the derived suggestion.
      await tester.enterText(
        find.byKey(const Key('worktree-path')),
        '/somewhere/else',
      );
      await tester.pump();
      // Further branch edits must not overwrite the manual choice.
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'feat/y',
      );
      await tester.pump();
      expect(find.widgetWithText(TextField, '/somewhere/else'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '/home/u/repo-feat-y'),
        findsNothing,
      );
    });
  });

  testWidgets('flags an existing, non-empty destination directory', (
    tester,
  ) async {
    await _onDesktop(() async {
      await _open(tester, isNonEmptyDir: (path) => path == '/home/u/occupied');
      await tester.enterText(
        find.byKey(const Key('worktree-path')),
        '/home/u/occupied',
      );
      await tester.enterText(
        find.byKey(const Key('worktree-new-branch')),
        'ok',
      );
      await tester.pump();
      expect(find.text('That directory is not empty'), findsOneWidget);
    });
  });

  testWidgets('remove dialog names the path and returns the choice', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                answer = await showRemoveWorktreeDialog(context, _existing[1]);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/home/u/repo-login'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('force dialog quotes git and offers Force remove', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                answer = await showForceRemoveDialog(
                  context,
                  _existing[1],
                  'fatal: contains modified or untracked files, use --force',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('contains modified or untracked files'),
      findsOneWidget,
    );
    await tester.tap(find.text('Force remove'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('collision dialog offers three actions and names the holder', (
    tester,
  ) async {
    CollisionChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showWorktreeCollisionDialog(
                  context,
                  branch: 'feat/login',
                  holder: _existing[1],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/home/u/repo-login'), findsOneWidget);
    expect(find.text('Open worktree'), findsOneWidget);
    expect(find.text('Checkout anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Open worktree'));
    await tester.pumpAndSettle();
    expect(choice, CollisionChoice.openWorktree);
  });

  testWidgets('collision dialog: checkout anyway', (tester) async {
    CollisionChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showWorktreeCollisionDialog(
                  context,
                  branch: 'feat/login',
                  holder: _existing[1],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout anyway'));
    await tester.pumpAndSettle();
    expect(choice, CollisionChoice.checkoutAnyway);
  });

  testWidgets('collision dialog: cancel', (tester) async {
    CollisionChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showWorktreeCollisionDialog(
                  context,
                  branch: 'feat/login',
                  holder: _existing[1],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(choice, CollisionChoice.cancel);
  });

  testWidgets('prune dialog shows the dry-run report verbatim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPruneDialog(
                context,
                'Removing worktrees/gone: gitdir file points to '
                'non-existent location',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Removing worktrees/gone'), findsOneWidget);
    expect(find.text('Prune'), findsOneWidget);
  });
}
