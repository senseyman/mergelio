import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/hooks.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/hooks.dart';
import 'package:mergelio/ui/workspace/hooks_panel.dart';

class _FakeHookActions implements HookActions {
  final calls = <String>[];

  @override
  String get repoPath => '/r';

  @override
  Future<bool> setEnabled(
    String dir,
    String name, {
    required bool enabled,
  }) async {
    calls.add('${enabled ? 'enable' : 'disable'} $dir/$name');
    return true;
  }

  @override
  Future<bool> save(String dir, String name, String text) async {
    calls.add('save $dir/$name');
    return true;
  }

  @override
  Future<bool> useSample(String dir, String name) async {
    calls.add('sample $dir/$name');
    return true;
  }
}

Widget _harness(HookInventory inv, _FakeHookActions actions) => ProviderScope(
  overrides: [
    hookInventoryProvider.overrideWith((ref, path) async => inv),
    hookActionsProvider.overrideWith((ref, path) => actions),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: const Scaffold(
      body: SingleChildScrollView(child: HooksPanel(repoPath: '/r')),
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
}
