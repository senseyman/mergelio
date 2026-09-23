// A bisect leaves the repository on a detached HEAD, so quitting or closing
// its tab while one is running needs to ask first — the single sharpest edge
// in the whole feature is a guard that outlives the bar and blocks quitting
// forever, or one that never registers and lets a detached HEAD slip by
// unannounced.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/open_files.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/unsaved_guard.dart';
import 'package:mergelio/ui/files/file_editor_pane.dart';
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

/// Drives a single [bisectStateProvider] through a sequence of answers so a
/// test can pin what the guard does to a *change* of answer rather than to
/// one frozen state.
enum _Phase { running, unreadable, none }

final _readPhase = StateProvider<_Phase>((ref) => _Phase.running);

Override _phased() => bisectStateProvider('/r').overrideWith((ref) {
  switch (ref.watch(_readPhase)) {
    case _Phase.running:
      return _running();
    case _Phase.unreadable:
      return Future<BisectState?>.error(StateError('git unavailable'));
    case _Phase.none:
      return null;
  }
});

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

  // A read that failed, or has not landed yet, says nothing about the
  // repository — and that cuts both ways. It cannot drop a guard a confirmed
  // bisect armed, because the detached HEAD may well still be there; and it
  // cannot arm one, because prompting about a hunt nobody has been told
  // exists is how opening a tab and quitting again turns into a warning for
  // a repository that was never bisecting.
  group('a bisect state that is not known', () {
    ProviderContainer unreadable() {
      final container = ProviderContainer(
        overrides: [
          bisectStateProvider('/r').overrideWith(
            (ref) => Future<BisectState?>.error(StateError('git unavailable')),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('a first load still in flight registers no guard', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          bisectStateProvider('/r')
              .overrideWith((ref) => Completer<BisectState?>().future),
        ],
      );
      addTearDown(container.dispose);
      await _pumpBar(tester, container);

      // Nothing has confirmed a bisect, so there is nothing to warn about:
      // the confirm goes straight through without a dialog.
      expect(await _confirmAndDismiss(tester, container), isTrue);
    });

    testWidgets('a persistent error with no earlier answer registers no '
        'guard', (tester) async {
      final container = unreadable();
      await _pumpBar(tester, container);

      // Every quit would otherwise prompt, and the dialog's Reset could not
      // help: there is no bisect anyone knows of to reset.
      expect(await _confirmAndDismiss(tester, container), isTrue);
    });

    testWidgets('says so rather than vanishing', (tester) async {
      final container = unreadable();
      await _pumpBar(tester, container);

      expect(find.text('Bisect state could not be read'), findsOneWidget);
    });

    testWidgets('an error after a confirmed bisect keeps the guard', (
      tester,
    ) async {
      final container = ProviderContainer(overrides: [_phased()]);
      addTearDown(container.dispose);
      await _pumpBar(tester, container);

      container.read(_readPhase.notifier).state = _Phase.unreadable;
      await tester.pumpAndSettle();

      // The hunt is still on and the repository still detached; a read that
      // momentarily failed must not be read as "the bisect went away".
      expect(await _confirmAndDismiss(tester, container), isFalse);
    });

    testWidgets('a confirmed bisect that ends drops the guard', (tester) async {
      final container = ProviderContainer(overrides: [_phased()]);
      addTearDown(container.dispose);
      await _pumpBar(tester, container);

      container.read(_readPhase.notifier).state = _Phase.none;
      await tester.pumpAndSettle();

      // Only git saying so is allowed to drop the guard.
      expect(await _confirmAndDismiss(tester, container), isTrue);
    });
  });

  // Graph mode and Files mode are two branches of the same build, so one
  // repository's bar and its editor pane swap places inside a single frame:
  // the arriving widget registers its guard before the departing one is
  // disposed. Both hold a guard on the same repository path, and neither may
  // take the other's with it.
  group('switching between the graph and Files', () {
    ProviderContainer containerFor() {
      final container = ProviderContainer(
        overrides: [
          bisectStateProvider('/r').overrideWith((ref) => _running()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          editableFileForPathProvider.overrideWith(
            (ref, FileRef key) async =>
                EditableFile(text: 'body of ${key.relPath}'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> pumpEditor(WidgetTester tester, ProviderContainer container) =>
        _pump(
          tester,
          container,
          const SizedBox(
            width: 800,
            height: 600,
            child: FileEditorPane(repoPath: '/r'),
          ),
        );

    Future<void> dirtyAFile(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container.read(openFilesProvider('/r').notifier).open('README.md');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'changed');
      await tester.pumpAndSettle();
      expect(container.read(openFilesProvider('/r')).dirty, {'README.md'});
    }

    testWidgets('leaving Files mid-bisect keeps the quit guard', (
      tester,
    ) async {
      final container = containerFor();
      await pumpEditor(tester, container);
      await dirtyAFile(tester, container);

      await _pumpBar(tester, container);

      // The editor is gone and its unsaved text with it, but the repository
      // is still on the bisect's detached HEAD, so the bar's guard has to be
      // the one still standing.
      expect(await _confirmAndDismiss(tester, container), isFalse);
    });

    testWidgets('entering Files mid-bisect keeps the unsaved-text guard', (
      tester,
    ) async {
      final container = containerFor();
      await _pumpBar(tester, container);
      await pumpEditor(tester, container);
      await dirtyAFile(tester, container);

      final confirmed = container.read(unsavedGuardsProvider).confirm('/r');
      await tester.pumpAndSettle();
      // Unsaved text is what the editor's guard exists to protect; closing
      // over it without a word is the loss this seam can cause.
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await confirmed, isFalse);
    });
  });
}
