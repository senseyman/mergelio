// A bisect leaves the repository on a detached HEAD, so quitting or closing
// its tab while one is running needs to ask first — the single sharpest edge
// in the whole feature is a guard that outlives the bar and blocks quitting
// forever, or one that never registers and lets a detached HEAD slip by
// unannounced.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/unsaved_guard.dart';
import 'package:mergelio/ui/graph/bisect_bar.dart';

BisectState _running() => const BisectState(
  marks: [
    BisectMark('aaa', BisectKind.bad),
    BisectMark('bbb', BisectKind.good),
  ],
  startBranch: 'main',
  terms: BisectTerms(),
  currentSha: 'ccc11111',
  revisionsLeft: 3,
  steps: 2,
  firstBad: null,
);

BisectState _finished() => const BisectState(
  marks: [BisectMark('aaa', BisectKind.bad)],
  startBranch: 'main',
  terms: BisectTerms(),
  currentSha: 'aaa',
  revisionsLeft: 0,
  steps: 0,
  firstBad: 'aaa',
);

void _noop(String sha) {}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBar(WidgetTester tester, ProviderContainer container) =>
    _pump(
      tester,
      container,
      const BisectBar(repoPath: '/r', onJumpToCommit: _noop),
    );

Future<void> _pumpEmpty(WidgetTester tester, ProviderContainer container) =>
    _pump(tester, container, const SizedBox.shrink());

/// Consults the guard and, if it opened the quit dialog, dismisses the
/// barrier — the same outcome as pressing Escape — which answers "cancel".
Future<bool> _confirmAndDismiss(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final confirmed = container.read(unsavedGuardsProvider).confirm('/r');
  await tester.pump();
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
  return confirmed;
}

void main() {
  testWidgets('a running bisect registers a quit guard', (tester) async {
    final container = ProviderContainer(
      overrides: [bisectStateProvider('/r').overrideWith((ref) => _running())],
    );
    addTearDown(container.dispose);
    await _pumpBar(tester, container);

    // With the bar mounted, confirming the repo goes through the guard,
    // which opens the quit dialog. Dismissing it without choosing anything
    // is the safe default: cancel.
    expect(await _confirmAndDismiss(tester, container), isFalse);
  });

  testWidgets('a finished bisect still registers a quit guard', (tester) async {
    final container = ProviderContainer(
      overrides: [bisectStateProvider('/r').overrideWith((ref) => _finished())],
    );
    addTearDown(container.dispose);
    await _pumpBar(tester, container);

    // A finished bisect still sits on the detached HEAD until it is reset,
    // so the guard must not drop just because the hunt is over.
    expect(await _confirmAndDismiss(tester, container), isFalse);
  });

  testWidgets('no bisect registers no guard', (tester) async {
    final container = ProviderContainer(
      overrides: [bisectStateProvider('/r').overrideWith((ref) => null)],
    );
    addTearDown(container.dispose);
    await _pumpBar(tester, container);

    expect(await container.read(unsavedGuardsProvider).confirm('/r'), isTrue);
  });

  testWidgets('unmounting the bar removes the guard', (tester) async {
    final container = ProviderContainer(
      overrides: [bisectStateProvider('/r').overrideWith((ref) => _running())],
    );
    addTearDown(container.dispose);
    await _pumpBar(tester, container);
    await _pumpEmpty(tester, container);

    // A guard that outlives its widget blocks quitting the repository
    // forever — the bug this guard exists to avoid.
    expect(await container.read(unsavedGuardsProvider).confirm('/r'), isTrue);
  });
}
