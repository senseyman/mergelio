import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/l10n.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_bootstrap.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

/// Answers every git call with [result], or throws [error] when set.
class _FakeGit implements GitService {
  GitResult result = const GitResult(0, '', '');
  Object? error;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  final uk = lookupAppLocalizations(const Locale('uk'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('appLocalizationsFor', () {
    test('a chosen language wins over the system one', () {
      expect(
        appLocalizationsFor('uk', const [Locale('en', 'US')]).localeName,
        'uk',
      );
    });

    test('no choice follows the first supported system language', () {
      expect(
        appLocalizationsFor('', const [
          Locale('fr'),
          Locale('uk', 'UA'),
          Locale('en'),
        ]).localeName,
        'uk',
      );
    });

    test('nothing supported falls back to English', () {
      expect(appLocalizationsFor('', const [Locale('fr')]).localeName, 'en');
      expect(appLocalizationsFor('xx', const []).localeName, 'en');
    });
  });

  test('without the app override the state layer speaks English', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(appL10nProvider).localeName, 'en');
  });

  test('the app override follows the language setting', () {
    final settings = SettingsController(
      InMemorySettingsRepository(),
      const AppSettings(localeCode: 'uk'),
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        appL10nOverride,
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(appL10nProvider).localeName, 'uk');
    settings.setLocaleCode('en');
    expect(container.read(appL10nProvider).localeName, 'en');
  });

  group('repo actions toast in the chosen language', () {
    late _FakeGit git;
    late ProviderContainer container;
    late RepoActions actions;

    setUp(() {
      git = _FakeGit();
      container = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          appL10nProvider.overrideWithValue(uk),
        ],
      );
      actions = container.read(repoActionsProvider('/r'));
      addTearDown(container.dispose);
    });

    List<String> titles() => [
      for (final t in container.read(toastProvider)) t.title,
    ];

    test('a busy lane is refused in Ukrainian', () async {
      container.read(fetchBusyProvider.notifier).state = const BusyState('x');
      await actions.pruneRemote('origin');
      expect(titles(), [uk.actBusy]);
      expect(uk.actBusy, isNot(en.actBusy));
    });

    test('success names the localized operation', () async {
      await actions.pruneRemote('origin');
      expect(titles(), [uk.actComplete(uk.actPruneRemote('origin'))]);
    });

    test('a git failure names the localized operation', () async {
      git.result = const GitResult(1, '', 'rejected');
      await actions.pruneRemote('origin');
      expect(titles(), [uk.actFailed(uk.actPruneRemote('origin'))]);
      expect(container.read(toastProvider).single.description, 'rejected');
    });

    test('an unexpected error is described in Ukrainian', () async {
      git.error = StateError('boom');
      await actions.pruneRemote('origin');
      expect(titles(), [uk.actFailed(uk.actPruneRemote('origin'))]);
      expect(
        container.read(toastProvider).single.description,
        uk.actUnexpectedError,
      );
    });

    test('the busy bar shows the localized label', () async {
      String? seen;
      final sub = container.listen(fetchBusyProvider, (_, next) {
        seen ??= next?.label;
      });
      addTearDown(sub.close);
      await actions.pruneRemote('origin');
      expect(seen, uk.actPruneRemote('origin'));
    });

    test('an empty commit message is refused in Ukrainian', () async {
      await actions.rewordCommit('abc', '   ');
      expect(titles(), [uk.actCommitMessageEmpty]);
    });

    test('a refused clone is reported in Ukrainian', () async {
      final path = await container
          .read(repoBootstrapProvider)
          .clone(url: '', parentDir: '/tmp');
      expect(path, isNull);
      final toast = container.read(toastProvider).single;
      expect(toast.title, uk.actFailed(uk.bootClone));
      expect(toast.description, uk.bootUrlDestRequired);
    });
  });
}
