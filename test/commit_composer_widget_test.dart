import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/commit_message.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/commit_composer.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _FakeGit implements GitService {
  /// What `git log -1 --format=%B` answers: HEAD's message, for amend.
  final String headMessage;
  _FakeGit([this.headMessage = '']);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => args.first == 'log'
      ? GitResult(0, headMessage, '')
      : const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

typedef _Call = ({
  String summary,
  String description,
  bool signoff,
  List<String> coauthors,
  List<CommitTrailer> trailers,
});

class _FakeActions implements RepoActions {
  final calls = <_Call>[];
  var mergeMessage = '';

  @override
  Future<String> pendingMergeMessage() async => mergeMessage;

  @override
  Future<CommitOutcome> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    bool noVerify = false,
    bool signoff = false,
    List<String> coauthors = const [],
    List<CommitTrailer> trailers = const [],
  }) async {
    calls.add((
      summary: summary,
      description: description,
      signoff: signoff,
      coauthors: coauthors,
      trailers: trailers,
    ));
    return const CommitOutcome(committed: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A store whose drafts arrive only once [release] is called, to hold the
/// composer in the moment before its branch's draft has loaded.
class _SlowStore implements KeyValueStore {
  final inner = InMemoryKeyValueStore();
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<String?> get(String key) async {
    if (key.startsWith('composer:drafts:')) await _gate.future;
    return inner.get(key);
  }

  @override
  Future<void> put(String key, String value) => inner.put(key, value);
}

const _staged = WorkingFile(path: 'staged.txt', index: GitChange.modified);

RepoData _data(String branch) => RepoData(
  working: const [_staged],
  branches: [Branch(name: branch, current: true)],
);

Widget _harness(
  _FakeActions actions,
  KeyValueStore kv, {
  String branch = 'main',
  String template = '',
  List<Issue> issues = const [],
  String headMessage = '',
  PendingOp? pending,
  Future<void>? templateGate,
}) => ProviderScope(
  overrides: [
    lfsLocksProvider.overrideWith((ref, repo) async => LfsLockState.none),
    gitServiceProvider.overrideWithValue(_FakeGit(headMessage)),
    pendingOpProvider('/r').overrideWith((ref) async => pending),
    repoActionsProvider.overrideWith((ref, path) => actions),
    kvStoreProvider.overrideWithValue(kv),
    commitTemplateProvider.overrideWith((ref, path) async {
      await templateGate;
      return (text: template, commentChar: '#');
    }),
    issuePanelProvider.overrideWith((ref, path) async => issues),
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
      body: WorkingTreePanel(repoPath: '/r', data: _data(branch)),
    ),
  ),
);

Finder _field(String hint) => find.widgetWithText(TextField, hint);

String _text(WidgetTester tester, String hint) =>
    tester.widget<TextField>(_field(hint)).controller!.text;

Future<void> _pump(WidgetTester tester, Widget w) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Composer options'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Conventional Commits mode composes the subject', (tester) async {
    final kv = InMemoryKeyValueStore();
    await ComposerStore(
      kv,
      '/r',
    ).savePrefs(const ComposerPrefs(conventional: true));
    final actions = _FakeActions();
    await _pump(tester, _harness(actions, kv));

    await tester.tap(find.text('no type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feat').last);
    await tester.pumpAndSettle();
    await tester.enterText(_field('scope'), 'ui');
    await tester.tap(find.text('Breaking'));
    await tester.enterText(_field('Summary'), 'add composer');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(actions.calls.single.summary, 'feat(ui)!: add composer');
  });

  testWidgets('turning Conventional Commits on parses what is typed', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await _pump(tester, _harness(_FakeActions(), kv));
    await tester.enterText(_field('Summary'), 'fix(git): stop at break');
    await _openMenu(tester);
    await tester.tap(find.text('Conventional Commits'));
    await tester.pumpAndSettle();

    expect(_text(tester, 'Summary'), 'stop at break');
    expect(_text(tester, 'scope'), 'git');
    expect((await ComposerStore(kv, '/r').prefs()).conventional, isTrue);
  });

  testWidgets('the meter counts the subject against the limit', (tester) async {
    final kv = InMemoryKeyValueStore();
    await _pump(tester, _harness(_FakeActions(), kv));
    await tester.enterText(_field('Summary'), 'x' * 80);
    await tester.pump();
    expect(find.text('80/72'), findsOneWidget);

    await _openMenu(tester);
    await tester.tap(find.text('Subject limit: 100'));
    await tester.pumpAndSettle();
    expect(find.text('80/100'), findsOneWidget);
  });

  testWidgets('a template fills the empty composer and must be edited', (
    tester,
  ) async {
    final actions = _FakeActions();
    final kv = InMemoryKeyValueStore();
    await _pump(tester, _harness(actions, kv, template: 'Area: \n\nWhy:'));
    expect(_text(tester, 'Summary'), 'Area:');
    expect(_text(tester, 'Description'), 'Why:');
    // Untouched template text is not a draft worth keeping.
    await tester.pump(const Duration(seconds: 1));
    expect(await ComposerStore(kv, '/r').draft('main'), isNull);

    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);
    final toasts = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    ).read(toastProvider);
    expect(toasts.map((t) => t.title), contains('Edit the template first'));

    await tester.enterText(_field('Summary'), 'Area: parser');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls.single.summary, 'Area: parser');
    // The next message starts from the template again.
    expect(_text(tester, 'Summary'), 'Area:');
  });

  testWidgets('trailers and sign-off reach the commit', (tester) async {
    final actions = _FakeActions();
    await _pump(tester, _harness(actions, InMemoryKeyValueStore()));
    await tester.enterText(_field('Summary'), 'S');
    await tester.tap(find.text('Trailers'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('Co-authors: Name <email>, Name2 <email2>'),
      'A <a@x>',
    );
    await tester.enterText(_field('Refs: #12, #34'), '12');
    await tester.enterText(_field('Fixes: #12'), '#3, #4');
    await tester.tap(find.text('Sign off'));
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    final call = actions.calls.single;
    expect(call.signoff, isTrue);
    expect(call.coauthors, ['A <a@x>']);
    expect(call.trailers, [
      (key: 'Refs', value: '#12'),
      (key: 'Fixes', value: '#3'),
      (key: 'Fixes', value: '#4'),
    ]);
  });

  testWidgets('issue references complete from the forge issues', (
    tester,
  ) async {
    await _pump(
      tester,
      _harness(
        _FakeActions(),
        InMemoryKeyValueStore(),
        issues: const [
          Issue(
            number: 12,
            title: 'Crash on start',
            state: IssueState.open,
            author: ForgeUser(login: 'a'),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Trailers'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Fixes: #12'), '#3, cra');
    await tester.pumpAndSettle();
    await tester.tap(find.text('#12 Crash on start'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Fixes: #12'), '#3, #12');
    // The pick is complete: the list does not reopen on the text it wrote.
    expect(find.text('#12 Crash on start'), findsNothing);
  });

  testWidgets('a committed message can be recalled', (tester) async {
    final kv = InMemoryKeyValueStore();
    final actions = _FakeActions();
    await _pump(tester, _harness(actions, kv));
    await tester.enterText(_field('Summary'), 'fix: old one');
    await tester.enterText(_field('Description'), 'with a body');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), '');

    await tester.tap(find.byTooltip('Recent messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fix: old one').last);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), 'fix: old one');
    expect(_text(tester, 'Description'), 'with a body');
  });

  testWidgets('a draft survives a branch switch and is dropped on commit', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    final actions = _FakeActions();
    await _pump(tester, _harness(actions, kv));
    // Switched inside the save debounce: the switch itself has to keep it.
    await tester.enterText(_field('Summary'), 'half done');

    await tester.pumpWidget(_harness(actions, kv, branch: 'topic'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), '');

    await tester.pumpWidget(_harness(actions, kv));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), 'half done');

    await tester.tap(find.text('Commit'));
    await tester.pump();
    expect(await ComposerStore(kv, '/r').draft('main'), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('a draft typed just before the composer closes is kept', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await _pump(tester, _harness(_FakeActions(), kv));
    await tester.enterText(_field('Summary'), 'last words');
    // Gone before the save debounce fires: stashing everything does this.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(
      (await ComposerStore(kv, '/r').draft('main'))?.summary,
      'last words',
    );
  });

  testWidgets('turning Amend off clears the type row it filled in', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await ComposerStore(
      kv,
      '/r',
    ).savePrefs(const ComposerPrefs(conventional: true));
    final actions = _FakeActions();
    await _pump(
      tester,
      _harness(actions, kv, headMessage: 'feat(ui)!: old subject\n\nold body'),
    );
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'scope'), 'ui');

    await tester.tap(find.text('Amend').first);
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), '');
    expect(_text(tester, 'scope'), '');

    await tester.enterText(_field('Summary'), 'new subject');
    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();
    expect(actions.calls.single.summary, 'new subject');
  });

  testWidgets('an edited type row is kept when Amend turns off', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await ComposerStore(
      kv,
      '/r',
    ).savePrefs(const ComposerPrefs(conventional: true));
    await _pump(
      tester,
      _harness(_FakeActions(), kv, headMessage: 'feat(ui): old subject'),
    );
    await tester.tap(find.text('Amend'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('scope'), 'diff');
    await tester.tap(find.text('Amend').first);
    await tester.pumpAndSettle();
    expect(_text(tester, 'scope'), 'diff');
    expect(_text(tester, 'Summary'), 'old subject');
  });

  testWidgets('git\'s merge message is offered but not kept as a draft', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    final actions = _FakeActions()..mergeMessage = "Merge branch 'topic'";
    await _pump(
      tester,
      _harness(
        actions,
        kv,
        pending: const PendingOp(kind: MergeKind.merge, branch: 'topic'),
      ),
    );
    expect(_text(tester, 'Summary'), "Merge branch 'topic'");
    await tester.pump(const Duration(seconds: 1));
    expect(await ComposerStore(kv, '/r').draft('main'), isNull);

    // Once edited it is the user's, and kept.
    await tester.enterText(_field('Summary'), "Merge branch 'topic' early");
    await tester.pump(const Duration(seconds: 1));
    expect(
      (await ComposerStore(kv, '/r').draft('main'))?.summary,
      "Merge branch 'topic' early",
    );
  });

  testWidgets('a template read late does not replace git\'s merge message', (
    tester,
  ) async {
    final actions = _FakeActions()..mergeMessage = "Merge branch 'topic'";
    final gate = Completer<void>();
    await _pump(
      tester,
      _harness(
        actions,
        InMemoryKeyValueStore(),
        template: 'Area: ',
        pending: const PendingOp(kind: MergeKind.merge, branch: 'topic'),
        templateGate: gate.future,
      ),
    );
    expect(_text(tester, 'Summary'), "Merge branch 'topic'");
    gate.complete();
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), "Merge branch 'topic'");
  });

  testWidgets('a prepared fixup keeps the description already typed', (
    tester,
  ) async {
    await _pump(tester, _harness(_FakeActions(), InMemoryKeyValueStore()));
    await tester.enterText(_field('Description'), 'why it changed');
    final c = ProviderScope.containerOf(
      tester.element(find.byType(WorkingTreePanel)),
    );
    c.read(composerPrefillProvider('/r').notifier).state = 'fixup! Old';
    await tester.pumpAndSettle();
    expect(_text(tester, 'Summary'), 'fixup! Old');
    expect(_text(tester, 'Description'), 'why it changed');
  });

  testWidgets('the fields wait for the stored draft before taking input', (
    tester,
  ) async {
    final kv = _SlowStore();
    await kv.inner.put(
      'composer:drafts:/r',
      '{"main":{"summary":"stored draft"}}',
    );
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(_FakeActions(), kv));
    await tester.pump();
    expect(tester.widget<TextField>(_field('Summary')).readOnly, isTrue);

    kv.release();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field('Summary')).readOnly, isFalse);
    expect(_text(tester, 'Summary'), 'stored draft');
  });

  testWidgets('a stored draft is restored when the composer opens', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await ComposerStore(
      kv,
      '/r',
    ).saveDraft('main', const ComposerDraft(summary: 'kept', fixes: '#9'));
    await _pump(tester, _harness(_FakeActions(), kv, template: 'T'));
    expect(_text(tester, 'Summary'), 'kept');
    // Trailer fields with content open on their own.
    expect(_text(tester, 'Fixes: #12'), '#9');
  });

  testWidgets('wrap rewraps the description to 72 columns', (tester) async {
    await _pump(tester, _harness(_FakeActions(), InMemoryKeyValueStore()));
    await tester.enterText(
      _field('Description'),
      List.filled(30, 'word').join(' '),
    );
    await _openMenu(tester);
    await tester.tap(find.text('Wrap description to 72 columns'));
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'Description').split('\n').map((l) => l.length),
      everyElement(lessThanOrEqualTo(72)),
    );
  });

  testWidgets('the template editor saves a per-repo template', (tester) async {
    final kv = InMemoryKeyValueStore();
    await _pump(tester, _harness(_FakeActions(), kv));
    await _openMenu(tester);
    await tester.tap(find.text('Message template…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'Area: \n# hint',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await ComposerStore(kv, '/r').prefs()).template, 'Area: \n# hint');
  });

  for (final width in [336.0, 480.0]) {
    testWidgets('conventional row and toggles fit at ${width}px', (
      tester,
    ) async {
      final kv = InMemoryKeyValueStore();
      await ComposerStore(
        kv,
        '/r',
      ).savePrefs(const ComposerPrefs(conventional: true));
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness(_FakeActions(), kv));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Commit'), findsOneWidget);
    });
  }
}
