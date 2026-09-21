import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/reflog_section.dart';

const _fs = '\x1f';
const _rs = '\x00';

const _shaCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaReset = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _entry(String selector, String sha, String subject) => [
  sha,
  selector,
  subject,
  'Neo',
  'neo@example.com',
  '2026-09-15T12:34:56+01:00',
].join(_fs);

final _reflogOut = [
  _entry('HEAD@{0}', _shaCommit, 'commit: add thing'),
  _entry('HEAD@{1}', _shaReset, 'reset: moving to HEAD~1'),
].join(_rs);

/// A reflog of [n] entries, for exercising the truncation hint.
String _reflogOfLength(int n) => [
  for (var i = 0; i < n; i++)
    _entry('HEAD@{$i}', i.toRadixString(16).padLeft(40, '0'), 'commit: c$i'),
].join(_rs);

class _FakeGit implements GitService {
  final List<List<String>> calls = [];

  /// Fails the reflog read, as an unreadable repository would.
  final bool reflogFails;

  /// How many entries the reflog read returns. Null uses the two-entry fixture.
  final int? entryCount;

  _FakeGit({this.reflogFails = false, this.entryCount});

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
    if (args.contains('-g')) {
      if (reflogFails) {
        return GitResult(128, '', 'fatal: unable to read the reflog');
      }
      return GitResult(
        0,
        entryCount == null ? _reflogOut : _reflogOfLength(entryCount!),
        '',
      );
    }
    final out = switch (args.first) {
      'rev-parse' => 'deadbeef\n',
      'symbolic-ref' => 'main\n',
      // resetMixed captures the index tree first and bails out if it is empty.
      'write-tree' => 'cafebabecafebabecafebabecafebabecafebabe\n',
      _ => '',
    };
    return GitResult(0, out, '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;

  bool get readReflog => calls.any((c) => c.contains('-g'));
}

int _reads(_FakeGit git) => git.calls.where((c) => c.contains('-g')).length;

/// Pumps [ReflogSection] alone: the section owns its own git reads, so it
/// needs no repository data loaded behind it.
Future<ProviderContainer> _pumpSection(
  WidgetTester tester,
  _FakeGit git, {
  bool open = true,
  bool confirm = true,
  String dateFormat = 'medium',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(
              collapsedSections: {'reflog': !open},
              confirmDestructive: confirm,
              dateFormat: dateFormat,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        // Scrollable like the real sidebar: a full page of entries is far
        // taller than the test viewport.
        home: const Scaffold(
          body: SingleChildScrollView(child: ReflogSection(repoPath: '/r')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ReflogSection)));
}

void main() {
  testWidgets('reads HEAD reflog with a bounded count', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    final call = git.calls.firstWhere((c) => c.contains('-g'));
    expect(call.first, 'log');
    expect(call.any((a) => a.startsWith('--max-count=')), isTrue);
  });

  testWidgets('renders a row per entry, verb apart from the message', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    expect(find.text('HEAD@{0}'), findsOneWidget);
    expect(find.text('HEAD@{1}'), findsOneWidget);
    expect(find.text('commit'), findsOneWidget);
    expect(find.text('add thing'), findsOneWidget);
    expect(find.text('reset'), findsOneWidget);
    expect(find.text('moving to HEAD~1'), findsOneWidget);
  });

  testWidgets('a fresh install finds the section already collapsed', (
    tester,
  ) async {
    // Every other test here writes the collapse flag explicitly, so none of
    // them exercises what someone actually meets on first run: no stored
    // entry at all. This section is the one that reads the opposite way
    // round from the rest, and losing that default would spend a subprocess
    // on every repository anyone opens.
    final git = _FakeGit();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (_) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: ReflogSection(repoPath: '/r')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(git.readReflog, isFalse);
  });

  testWidgets('a collapsed section reads no reflog', (tester) async {
    // The section is collapsed by default, so opening a repository must not
    // pay for a reflog nobody asked to see.
    final git = _FakeGit();
    await _pumpSection(tester, git, open: false);

    expect(git.readReflog, isFalse);
  });

  testWidgets('checkout targets the sha of the row, not its selector', (
    tester,
  ) async {
    // A selector is only valid until the ref moves again; the sha is what the
    // entry is actually worth recovering.
    final git = _FakeGit();
    await _pumpSection(tester, git, confirm: false);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout this commit'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.first == 'checkout' && c.contains(_shaReset)),
      isTrue,
    );
  });

  testWidgets('the row menu offers branch-here and both resets', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    await tester.tap(find.text('HEAD@{0}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Create branch here'), findsOneWidget);
    expect(find.text('Reset here (--mixed)'), findsOneWidget);
    expect(find.text('Reset here (--hard)'), findsOneWidget);
  });

  testWidgets('an operation run from the reflog re-reads the reflog', (
    tester,
  ) async {
    // Every row action moves HEAD, which writes a new reflog entry. Leaving
    // the list as it was would hide the very operation it just performed.
    final git = _FakeGit();
    await _pumpSection(tester, git, confirm: false);
    final before = git.calls.where((c) => c.contains('-g')).length;

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout this commit'));
    await tester.pumpAndSettle();

    // Exactly one more, not one per rebuild: the listener is re-registered on
    // every build, and re-arming it would re-read on each frame.
    expect(_reads(git), before + 1);
  });

  testWidgets('a collapsed section stops reading, reopening reads once', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);
    expect(_reads(git), 1);

    // The header renders its label uppercased, so drive the toggle by its
    // icon instead of matching on casing.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(_reads(git), 1);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(_reads(git), 2);
  });

  testWidgets('repeated rebuilds still re-read once per operation', (
    tester,
  ) async {
    // The listener is registered during build, so it is registered again on
    // every rebuild. One kept per rebuild would multiply the re-reads that an
    // operation triggers.
    final git = _FakeGit();
    await _pumpSection(tester, git, confirm: false);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
    }
    final before = _reads(git);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout this commit'));
    await tester.pumpAndSettle();

    expect(_reads(git), before + 1);
  });

  testWidgets('reset --mixed from a row targets that entry', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git, confirm: false);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset here (--mixed)'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any(
        (c) =>
            c.first == 'reset' &&
            c.contains('--mixed') &&
            c.contains(_shaReset),
      ),
      isTrue,
    );
  });

  testWidgets('reset --hard from a row targets that entry', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git, confirm: false);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset here (--hard)'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any((c) => c.contains('--hard') && c.contains(_shaReset)),
      isTrue,
    );
  });

  testWidgets('a failed read says so rather than showing an empty reflog', (
    tester,
  ) async {
    // "No reflog entries" after a failed read is the worst available lie: it
    // tells someone hunting for lost commits that there is nothing to find.
    final git = _FakeGit(reflogFails: true);
    await _pumpSection(tester, git);

    expect(find.text('Could not read the reflog'), findsOneWidget);
    expect(find.text('No reflog entries'), findsNothing);
  });

  testWidgets('a full page warns that the reflog was cut short', (
    tester,
  ) async {
    final git = _FakeGit(entryCount: 200);
    await _pumpSection(tester, git);

    expect(find.text('Showing the first 200 entries'), findsOneWidget);
  });

  testWidgets('a short reflog carries no truncation warning', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    expect(find.textContaining('Showing the first'), findsNothing);
  });

  testWidgets('checkout asks before detaching HEAD', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checkout this commit'));
    await tester.pumpAndSettle();

    expect(find.text('Check out bbbbbbb?'), findsOneWidget);
    expect(git.calls.any((c) => c.first == 'checkout'), isFalse);
  });

  testWidgets('create branch here branches at that entry', (tester) async {
    final git = _FakeGit();
    await _pumpSection(tester, git);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create branch here'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rescue');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      git.calls.any(
        (c) =>
            c.first == 'branch' &&
            c.contains('rescue') &&
            c.contains(_shaReset),
      ),
      isTrue,
    );
  });

  testWidgets('copy SHA copies the full sha, not the selector', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final git = _FakeGit();
    await _pumpSection(tester, git);

    await tester.tap(find.text('HEAD@{1}'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy SHA'));
    await tester.pumpAndSettle();

    expect(copied, [_shaReset]);
  });

  testWidgets('clicking a row focuses that commit in the graph', (
    tester,
  ) async {
    // Same affordance the stash rows already offer: the graph scrolls to
    // whatever selectedCommitProvider holds.
    final git = _FakeGit();
    final container = await _pumpSection(tester, git);

    await tester.tap(find.text('HEAD@{1}'));
    await tester.pumpAndSettle();

    expect(container.read(selectedCommitProvider), _shaReset);
  });

  testWidgets('rows date the entry, honouring the date-format setting', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pumpSection(tester, git, dateFormat: 'iso');

    // Both fixture entries carry the same timestamp.
    expect(find.text('2026-09-15'), findsNWidgets(2));
  });

  testWidgets('a short reflog offers no filter', (tester) async {
    // A filter is clutter until the list is too long to scan.
    final git = _FakeGit();
    await _pumpSection(tester, git);

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a long reflog can be filtered down', (tester) async {
    final git = _FakeGit(entryCount: 40);
    await _pumpSection(tester, git);

    await tester.enterText(find.byType(TextField), 'c7');
    await tester.pumpAndSettle();

    // Assert on selectors, not on the message: find.text also matches the
    // filter field's own contents, which are the query itself.
    expect(find.text('HEAD@{7}'), findsOneWidget);
    expect(find.text('HEAD@{8}'), findsNothing);
  });

  testWidgets('a filter matching nothing says so, not "no entries"', (
    tester,
  ) async {
    final git = _FakeGit(entryCount: 40);
    await _pumpSection(tester, git);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No matching entries'), findsOneWidget);
    expect(find.text('No reflog entries'), findsNothing);
  });
}
