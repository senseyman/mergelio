import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/hooks.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/hooks_panel.dart';

class _FakeHookActions implements HookActions {
  final calls = <String>[];

  /// What every write answers with; null is success.
  HookWriteException? failWith;

  @override
  String get repoPath => '/r';

  @override
  Future<HookWriteException?> setEnabled(
    String dir,
    String name, {
    required bool enabled,
  }) async {
    calls.add('${enabled ? 'enable' : 'disable'} $dir/$name');
    return failWith;
  }

  @override
  Future<HookWriteException?> save(String dir, String name, String text) async {
    calls.add('save $dir/$name');
    return failWith;
  }

  @override
  Future<HookWriteException?> useSample(String dir, String name) async {
    calls.add('sample $dir/$name');
    return failWith;
  }
}

Widget _harness(HookInventory inv, _FakeHookActions actions) => ProviderScope(
  overrides: [
    hookInventoryProvider.overrideWith((ref, path) async => inv),
    hookActionsProvider.overrideWith((ref, path) => actions),
    // The real one reads the hook file from disk.
    editableFileForPathProvider.overrideWith(
      (ref, key) async => const EditableFile(text: '#!/bin/sh\nexit 0\n'),
    ),
    settingsProvider.overrideWith(
      (ref) =>
          SettingsController(InMemorySettingsRepository(), const AppSettings()),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              onPressed: () => showHooksPanel(context, '/r'),
              child: const Text('open'),
            ),
            const Expanded(
              child: SingleChildScrollView(child: HooksPanel(repoPath: '/r')),
            ),
          ],
        ),
      ),
    ),
  ),
);

const _inv = HookInventory(
  dir: '/r/.git/hooks',
  hooks: [
    HookFile('pre-commit', HookState.active, hasSample: true),
    HookFile('pre-push', HookState.disabled),
    HookFile('pre-rebase', HookState.sample),
  ],
);

void main() {
  for (final width in [336.0, 760.0]) {
    testWidgets('lists each hook with its state at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(_inv, _FakeHookActions()));
      await tester.pumpAndSettle();
      expect(find.text('pre-commit'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Sample'), findsOneWidget);
      expect(find.text('/r/.git/hooks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the switch enables and disables through the actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeHookActions();
    await tester.pumpWidget(_harness(_inv, actions));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hook:switch:pre-commit')));
    await tester.tap(find.byKey(const ValueKey('hook:switch:pre-push')));
    await tester.pumpAndSettle();
    expect(actions.calls, [
      'disable /r/.git/hooks/pre-commit',
      'enable /r/.git/hooks/pre-push',
    ]);
  });

  testWidgets('a sample can be put to use', (tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeHookActions();
    await tester.pumpWidget(_harness(_inv, actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use sample'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['sample /r/.git/hooks/pre-rebase']);
  });

  testWidgets('core.hooksPath and a hook manager are called out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        const HookInventory(
          dir: '/r/.husky/_',
          customPath: '.husky/_',
          manager: HookManager.husky,
        ),
        _FakeHookActions(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set by core.hooksPath: .husky/_'), findsOneWidget);
    expect(find.textContaining('Managed by husky'), findsOneWidget);
    expect(find.text('No hooks in this repository.'), findsOneWidget);
  });

  testWidgets('closing the hook editor with unsaved text asks first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeHookActions();
    await tester.pumpWidget(_harness(_inv, actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit the pre-commit hook'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('editor:body')),
      '#!/bin/sh\nexit 1\n',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard edits?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit the pre-commit hook'), findsOneWidget);
    expect(actions.calls, isEmpty);

    // The title bar's close button goes through the same check.
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog).last,
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard edits?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Edit the pre-commit hook'), findsNothing);
  });

  testWidgets('closing an untouched hook editor just closes', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(_inv, _FakeHookActions()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Discard edits?'), findsNothing);
    expect(find.text('Edit the pre-commit hook'), findsNothing);
  });

  testWidgets('a symlinked hook has no switch to flip', (tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeHookActions();
    await tester.pumpWidget(
      _harness(
        const HookInventory(
          dir: '/r/.git/hooks',
          hooks: [HookFile('pre-commit', HookState.active, isLink: true)],
        ),
        actions,
      ),
    );
    await tester.pumpAndSettle();
    final sw = tester.widget<Switch>(
      find.byKey(const ValueKey('hook:switch:pre-commit')),
    );
    expect(sw.onChanged, isNull);
    expect(
      find.byTooltip(
        'Linked to a file elsewhere — change its mode there, so the change '
        'is not made behind your back.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a refused change is reported in words', (tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _FakeHookActions()
      ..failWith = HookWriteException(
        HookWriteFailure.alreadyExists,
        '/r/.git/hooks/pre-rebase',
      );
    await tester.pumpWidget(_harness(_inv, actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use sample'));
    await tester.pumpAndSettle();
    final toast = ProviderScope.containerOf(
      tester.element(find.byType(HooksPanel)),
    ).read(toastProvider).single;
    expect(toast.title, 'Could not change the pre-rebase hook');
    expect(toast.description, 'A hook with this name already exists.');
    expect(toast.kind, ToastKind.error);
  });
}
