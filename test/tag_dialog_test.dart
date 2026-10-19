import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/shell/repo_op_dialogs.dart';

/// Records every git call; answers the signing-config read from [config]
/// (once [configReady] completes), succeeds with no output otherwise.
class _FakeGit implements GitService {
  final Map<String, String> config;
  final Future<void>? configReady;
  _FakeGit(this.config, {this.configReady});

  final calls = <List<String>>[];

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
    if (args.first == 'config' && args.contains('--get-regexp')) {
      await configReady;
      if (config.isEmpty) return const GitResult(1, '', '');
      final out = [
        for (final e in config.entries)
          '${e.key.toLowerCase()}\n${e.value}\x00',
      ].join();
      return GitResult(0, out, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  /// The `git tag` command the dialog ran, from `tag` on.
  List<String>? get tag {
    for (final c in calls) {
      final i = c.indexOf('tag');
      if (i >= 0 && !c.contains('-d')) return c.sublist(i);
    }
    return null;
  }
}

Future<_FakeGit> _open(
  WidgetTester tester, {
  Map<String, String> config = const {},
  Future<void>? configReady,
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final git = _FakeGit(config, configReady: configReady);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        repoDataProvider.overrideWith((ref, path) async => const RepoData()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showTagDialog(context, ref, '/r', at: 'abc123'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return git;
}

Finder _signBox() => find.widgetWithText(CheckboxListTile, 'Sign tag');

bool _signed(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(_signBox()).value ?? false;

bool _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

Future<void> _create(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField).first, name);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unsigned by default; a lightweight tag says so to git', (
    tester,
  ) async {
    final git = await _open(tester);
    expect(_signed(tester), isFalse);
    await _create(tester, 'v1');
    expect(git.tag, ['tag', '--no-sign', 'v1', 'abc123']);
  });

  testWidgets('starts signed when the repo signs commits', (tester) async {
    await _open(tester, config: {'commit.gpgsign': 'true'});
    expect(_signed(tester), isTrue);
    expect(_chip(tester, 'annotated'), isTrue);
  });

  testWidgets('an explicit tag.gpgSign off wins over commit signing', (
    tester,
  ) async {
    await _open(
      tester,
      config: {'commit.gpgsign': 'true', 'tag.gpgSign': 'false'},
    );
    expect(_signed(tester), isFalse);
  });

  testWidgets('signing picks annotated; lightweight drops signing', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(_signBox());
    await tester.pumpAndSettle();
    expect(_chip(tester, 'annotated'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'lightweight'));
    await tester.pumpAndSettle();
    expect(_signed(tester), isFalse);
  });

  testWidgets('signs with the configured key, message defaulting to the name', (
    tester,
  ) async {
    final git = await _open(
      tester,
      config: {'commit.gpgsign': 'true', 'user.signingkey': '~/.ssh/id.pub'},
    );
    // The configured key is shown as the hint, not filled in.
    expect(find.text('~/.ssh/id.pub'), findsOneWidget);
    await _create(tester, 'v1');
    expect(git.tag, ['tag', '-s', '-m', 'v1', 'v1', 'abc123']);
  });

  testWidgets('a key typed in signs with that key', (tester) async {
    final git = await _open(tester, config: {'commit.gpgsign': 'true'});
    await tester.enterText(
      find.widgetWithText(TextField, 'Default key'),
      ' ABCD1234 ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tag message'),
      'Release',
    );
    await _create(tester, 'v1');
    expect(git.tag, ['tag', '-u', 'ABCD1234', '-m', 'Release', 'v1', 'abc123']);
  });

  testWidgets('unsigned annotated also says so to git', (tester) async {
    final git = await _open(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'annotated'));
    await tester.pumpAndSettle();
    expect(find.text('Signing key'), findsNothing);
    await _create(tester, 'v1');
    expect(git.tag, ['tag', '--no-sign', '-m', 'v1', 'v1', 'abc123']);
  });

  testWidgets('a signing default that arrives late does not flip a tag '
      'already being typed', (tester) async {
    final ready = Completer<void>();
    final git = await _open(
      tester,
      config: {'commit.gpgsign': 'true'},
      configReady: ready.future,
    );
    await tester.enterText(find.byType(TextField).first, 'v1');
    ready.complete();
    await tester.pumpAndSettle();
    expect(_signed(tester), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(git.tag, ['tag', '--no-sign', 'v1', 'abc123']);
  });

  testWidgets('the tag types are named in the app language', (tester) async {
    await _open(tester, locale: const Locale('uk'));
    expect(find.widgetWithText(ChoiceChip, 'легкий'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'анотований'), findsOneWidget);
    expect(find.text('lightweight'), findsNothing);
  });
}
