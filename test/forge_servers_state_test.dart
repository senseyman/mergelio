import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/forge_server.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

const _ghe = ForgeServer(kind: ForgeKind.github, host: 'ghe.corp', port: 8443);
const _gitlab = ForgeServer(kind: ForgeKind.gitlab, host: 'git.corp');

/// Answers `git credential fill` from [tokens], keyed by the `host=` line
/// the request carries, and records every request body.
class _Credentials implements GitService {
  final Map<String, String> tokens;
  final requests = <String>[];

  /// When set, every lookup waits on it — a helper that is slow or waiting
  /// on a keychain prompt.
  final Completer<void>? hang;
  _Credentials([this.tokens = const {}, this.hang]);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.length >= 2 && args[0] == 'credential') {
      requests.add(stdin ?? '');
      await hang?.future;
      final host = RegExp(
        r'^host=(.*)$',
        multiLine: true,
      ).firstMatch(stdin ?? '')?.group(1);
      final token = tokens[host];
      return token == null
          ? const GitResult(1, '', '')
          : GitResult(0, 'password=$token\n\n', '');
    }
    return const GitResult(1, '', 'unsupported');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _container({
  _Credentials? git,
  AppSettings settings = const AppSettings(),
  String remote = '',
}) {
  final c = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(git ?? _Credentials()),
      settingsProvider.overrideWith(
        (ref) => SettingsController(InMemorySettingsRepository(), settings),
      ),
      originRemoteUrlProvider.overrideWith((ref, path) async => remote),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// The account list once both clouds' token lookups have answered.
Future<List<ForgeServer>> _accounts(ProviderContainer c) async {
  for (final cloud in const [kGithubCloud, kGitlabCloud]) {
    await c.read(
      forgeAccountTokenProvider((host: cloud.credentialHost, path: null))
          .future,
    );
  }
  return c.read(forgeAccountListProvider(null));
}

void main() {
  group('server registry in settings', () {
    test('adds and removes a self-hosted server', () {
      final c = _container();
      final ctl = c.read(settingsProvider.notifier);

      ctl.addForgeServer(_ghe);
      ctl.addForgeServer(_gitlab);
      expect(c.read(forgeServersProvider), unorderedEquals([_ghe, _gitlab]));

      ctl.removeForgeServer(_ghe);
      expect(c.read(forgeServersProvider), [_gitlab]);
    });

    test('one server per host: a new port replaces the old entry', () {
      final c = _container();
      final ctl = c.read(settingsProvider.notifier);

      ctl.addForgeServer(_ghe);
      const moved = ForgeServer(kind: ForgeKind.github, host: 'ghe.corp');
      ctl.addForgeServer(moved);

      expect(c.read(forgeServersProvider), [moved]);
    });

    test('the clouds are never stored', () {
      final c = _container();
      c.read(settingsProvider.notifier).addForgeServer(kGithubCloud);
      expect(c.read(settingsProvider).forgeServers, isEmpty);
    });

    test('an entry this version cannot read is skipped, not fatal', () {
      final c = _container(
        settings: const AppSettings(
          forgeServers: {'ghe.corp:8443': 'github', 'x.corp': 'bitbucket'},
        ),
      );
      expect(c.read(forgeServersProvider), [_ghe]);
    });

    test('survives a settings round trip', () {
      const s = AppSettings(forgeServers: {'git.corp': 'gitlab'});
      expect(AppSettings.fromJson(s.toJson()).forgeServers, s.forgeServers);
    });
  });

  group('a repository on a registered server', () {
    test(
      'a self-hosted host matches exactly as registered, www. included',
      () async {
        // Unlike the clouds, www.corp and corp may be different servers.
        final c = _container(
          settings: const AppSettings(forgeServers: {'www.corp': 'gitlab'}),
          remote: 'git@corp:o/r.git',
        );
        expect(await c.read(forgeHostProvider('/r').future), isNull);
      },
    );

    test('resolves to that server', () async {
      final c = _container(
        settings: const AppSettings(forgeServers: {'ghe.corp:8443': 'github'}),
        remote: 'git@ghe.corp:o/r.git',
      );

      final host = await c.read(forgeHostProvider('/r').future);

      expect(host?.server, _ghe);
      expect(host?.projectPath, 'o/r');
    });

    test('is unknown until the server is registered', () async {
      final c = _container(remote: 'git@ghe.corp:o/r.git');
      expect(await c.read(forgeHostProvider('/r').future), isNull);

      c.read(settingsProvider.notifier).addForgeServer(_ghe);
      expect((await c.read(forgeHostProvider('/r').future))?.server, _ghe);
    });

    test('reads the token stored for host and port', () async {
      final git = _Credentials({'ghe.corp:8443': 'secret'});
      final c = _container(
        git: git,
        settings: const AppSettings(forgeServers: {'ghe.corp:8443': 'github'}),
        remote: 'https://ghe.corp/o/r.git',
      );

      final token = await c.read(forgeTokenProvider('/r').future);

      expect(token?.value, 'secret');
      expect(git.requests.single, contains('host=ghe.corp:8443\n'));
    });
  });

  group('forgeAccountListProvider', () {
    test('lists a cloud only when its token is on file', () async {
      final c = _container(git: _Credentials({'gitlab.com': 't'}));

      final list = await _accounts(c);

      expect(list, [kGitlabCloud]);
    });

    test(
      'lists every registered server, token or not, after the clouds',
      () async {
        final c = _container(
          git: _Credentials({'github.com': 't'}),
          settings: const AppSettings(
            forgeServers: {'git.corp': 'gitlab', 'ghe.corp:8443': 'github'},
          ),
        );

        final list = await _accounts(c);

        expect(list, [kGithubCloud, _ghe, _gitlab]);
      },
    );

    test('shows registered servers while the cloud lookups are pending', () {
      final hang = Completer<void>();
      final c = _container(
        git: _Credentials(const {'github.com': 't'}, hang),
        settings: const AppSettings(forgeServers: {'git.corp': 'gitlab'}),
      );

      // Not awaited: a helper stuck on a keychain prompt must not hide the
      // servers the registry already knows about.
      expect(c.read(forgeAccountListProvider(null)), [_gitlab]);
      hang.complete();
    });

    test('is empty with nothing connected and nothing registered', () async {
      final c = _container();
      expect(await _accounts(c), isEmpty);
    });
  });
}
