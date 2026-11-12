import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/net/proxied_client.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_network_overrides.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/net/proxy.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/network.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/update_controller.dart';

import 'support/hermetic_git.dart';

class _FakeGit implements GitService {
  _FakeGit(this.answer);
  final FutureOr<GitResult> Function(List<String> args) answer;
  final List<List<String>> calls = [];
  final List<String?> repos = [];

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
    repos.add(repoPath);
    return answer(args);
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => false;
}

ProviderContainer _container(
  _FakeGit git, {
  AppSettings settings = const AppSettings(),
  Map<String, String> env = const {},
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(git),
      proxyEnvironmentProvider.overrideWithValue(env),
      settingsProvider.overrideWith(
        (ref) => SettingsController(InMemorySettingsRepository(), settings),
      ),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return c;
}

final _api = Uri.parse('https://api.github.com/user');

void main() {
  group('gitHttpProxyProvider', () {
    test('reads global config, never whatever repo the app runs in', () async {
      // A repository's own http.proxy applies to that repository; the cwd
      // of the process is not a repository the user opened.
      final git = _FakeGit((_) => const GitResult(0, 'proxy.corp:3128\n', ''));
      final c = _container(git);
      expect(await c.read(gitHttpProxyProvider.future), 'proxy.corp:3128');
      expect(git.calls.single, ['config', '--global', '--get', 'http.proxy']);
      expect(git.repos.single, isNull);
    });

    test('falls back to system config when global has none', () async {
      final git = _FakeGit(
        (args) => args.contains('--system')
            ? const GitResult(0, 'sys.proxy:1\n', '')
            : const GitResult(1, '', ''),
      );
      final c = _container(git);
      expect(await c.read(gitHttpProxyProvider.future), 'sys.proxy:1');
      expect(git.calls.last, ['config', '--system', '--get', 'http.proxy']);
    });

    test('a global value, even empty, hides the system one', () async {
      final git = _FakeGit(
        (args) => args.contains('--system')
            ? const GitResult(0, 'sys.proxy:1\n', '')
            : const GitResult(0, '\n', ''),
      );
      final c = _container(git);
      expect(await c.read(gitHttpProxyProvider.future), '');
      expect(git.calls, hasLength(1));
    });

    test('unset is null and set-to-empty is empty', () async {
      final unset = _container(_FakeGit((_) => const GitResult(1, '', '')));
      expect(await unset.read(gitHttpProxyProvider.future), isNull);
      final empty = _container(_FakeGit((_) => const GitResult(0, '\n', '')));
      expect(await empty.read(gitHttpProxyProvider.future), '');
    });

    test('git failing to run reads as unset', () async {
      final c = _container(_FakeGit((_) => throw GitException('no git')));
      expect(await c.read(gitHttpProxyProvider.future), isNull);
    });
  });

  group('proxyPolicyProvider', () {
    test('combines settings, git and environment', () async {
      final c = _container(
        _FakeGit((_) => const GitResult(0, 'git.proxy:1\n', '')),
        env: {'HTTPS_PROXY': 'env.proxy:2'},
      );
      final p = await c.read(proxyPolicyProvider.future);
      expect(p.mode, ProxyMode.auto);
      expect(p.gitProxy, 'git.proxy:1');
      expect(p.env['HTTPS_PROXY'], 'env.proxy:2');
      expect((p.routeFor(_api) as ProxyVia).host, 'git.proxy');
    });

    test('follows the setting as it changes', () async {
      final c = _container(_FakeGit((_) => const GitResult(1, '', '')));
      final sub = c.listen(proxyPolicyProvider, (_, _) {});
      addTearDown(sub.close);
      expect((await c.read(proxyPolicyProvider.future)).mode, ProxyMode.auto);
      c.read(settingsProvider.notifier)
        ..setProxyMode(ProxyMode.manual)
        ..setProxyUrl('  http://typed:3128  ');
      final p = await c.read(proxyPolicyProvider.future);
      expect(p.mode, ProxyMode.manual);
      expect(p.manualUrl, 'http://typed:3128');
    });
  });

  group('git network overrides', () {
    test('follow the proxy settings', () {
      final c = _container(_FakeGit((_) => const GitResult(1, '', '')));
      expect(c.read(gitProxyOverridesProvider), same(GitNetworkOverrides.none));
      c.read(settingsProvider.notifier)
        ..setProxyMode(ProxyMode.manual)
        ..setProxyUrl('http://typed:1')
        ..setProxyForGit(true);
      expect(c.read(gitProxyOverridesProvider).config, {
        'http.proxy': 'http://typed:1',
      });
    });

    test('the git service applies them to network commands', () async {
      final c = ProviderContainer(
        overrides: [
          gitNetworkOverridesProvider.overrideWithValue(
            const GitNetworkOverrides(config: {'http.proxy': 'http://p:9'}),
          ),
        ],
      );
      addTearDown(c.dispose);
      final r = await c.read(gitServiceProvider).run([
        'config',
        '--get',
        'http.proxy',
      ], environment: networkEnv());
      expect(r.out, 'http://p:9');
    });
  });

  group('sshRemotesProvider', () {
    test('names the remotes whose effective url is ssh', () async {
      final git = _FakeGit(
        (args) => switch (args) {
          ['remote'] => const GitResult(0, 'origin\nupstream\nmirror\n', ''),
          [_, _, _, 'origin'] => const GitResult(
            0,
            'git@github.com:o/r.git\n',
            '',
          ),
          [_, _, _, 'upstream'] => const GitResult(0, 'https://h/r\n', ''),
          // An insteadOf rewrite is what --get-url reports, not the
          // configured https url.
          [_, _, _, 'mirror'] => const GitResult(0, 'ssh://git@h/r\n', ''),
          _ => const GitResult(1, '', ''),
        },
      );
      final c = _container(git);
      expect(await c.read(sshRemotesProvider('/repo').future), [
        'origin',
        'mirror',
      ]);
      expect(
        git.calls,
        contains(equals(['ls-remote', '--get-url', '--', 'origin'])),
      );
      expect(git.repos.toSet(), {'/repo'});
    });

    test('a remote whose name starts with a dash is still looked up', () async {
      final dir = Directory.systemTemp.createTempSync('ssh-remotes');
      addTearDown(() => dir.deleteSync(recursive: true));
      const git = HermeticGit();
      await git.run(['init', '-q'], repoPath: dir.path);
      await git.run([
        'remote',
        'add',
        '--',
        '-x',
        'git@h:r.git',
      ], repoPath: dir.path);
      final c = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(sshRemotesProvider(dir.path), (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(sshRemotesProvider(dir.path).future), ['-x']);
    });

    test('a repository git cannot read has none', () async {
      final c = _container(_FakeGit((_) => throw GitException('gone')));
      expect(await c.read(sshRemotesProvider('/repo').future), isEmpty);
    });
  });

  group('forge clients and the proxy policy', () {
    List<Override> forgeOverrides() => [
      originRemoteUrlProvider.overrideWith(
        (ref, path) async => 'https://github.com/o/r.git',
      ),
      forgeTokenProvider.overrideWith((ref, path) async => null),
    ];

    test('re-reading git config does not rebuild a live forge', () async {
      // Rebuilding the forge refetches every panel built on it, which spends
      // the rate budget; Preferences re-reads git config each time it opens.
      final c = _container(
        _FakeGit((_) => const GitResult(1, '', '')),
        extra: forgeOverrides(),
      );
      final sub = c.listen(forgeProvider('/repo'), (_, _) {});
      addTearDown(sub.close);
      final before = await c.read(forgeProvider('/repo').future);
      c.invalidate(gitHttpProxyProvider);
      await c.read(proxyPolicyProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(await c.read(forgeProvider('/repo').future), same(before));
    });

    test('changing the proxy setting rebuilds the forge', () async {
      final c = _container(
        _FakeGit((_) => const GitResult(1, '', '')),
        extra: forgeOverrides(),
      );
      final sub = c.listen(forgeProvider('/repo'), (_, _) {});
      addTearDown(sub.close);
      final before = await c.read(forgeProvider('/repo').future);
      c.read(settingsProvider.notifier).setProxyMode(ProxyMode.off);
      await Future<void>.delayed(Duration.zero);
      expect(await c.read(forgeProvider('/repo').future), isNot(same(before)));
    });
  });

  group('proxiedHttpClient', () {
    // A loopback server standing in for the proxy: whatever reaches it went
    // through the policy, because the target host does not exist.
    late HttpServer proxy;
    late List<HttpRequest> seen;

    setUp(() async {
      seen = [];
      proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      proxy.listen((req) {
        seen.add(req);
        req.response
          ..statusCode = 502
          ..close();
      });
    });
    tearDown(() => proxy.close(force: true));

    test('sends requests through the proxy the policy names', () async {
      final client = proxiedHttpClient(
        ProxyPolicy(
          mode: ProxyMode.manual,
          manualUrl: 'http://127.0.0.1:${proxy.port}',
        ),
      );
      addTearDown(client.close);
      final r = await client.get(Uri.parse('http://mergelio.invalid/x'));
      expect(r.statusCode, 502);
      expect(seen.single.uri.toString(), 'http://mergelio.invalid/x');
    });

    test('forge calls go through the proxy', () async {
      final c = _container(
        _FakeGit((_) => const GitResult(1, '', '')),
        settings: AppSettings(
          proxyMode: 'manual',
          proxyUrl: 'http://127.0.0.1:${proxy.port}',
        ),
        extra: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
        ],
      );
      // The budget read swallows its own failure; what matters is where it
      // went.
      expect(await c.read(forgeRateLimitProvider('/repo').future), isNull);
      expect(seen.single.method, 'CONNECT');
      expect(seen.single.uri.toString(), contains('api.github.com:443'));
    });

    test('an injected forge client still wins, with no git read', () async {
      final git = _FakeGit((_) => const GitResult(1, '', ''));
      final c = _container(
        git,
        extra: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          forgeHttpClientProvider.overrideWithValue(
            MockClient((req) async => http.Response('{}', 200)),
          ),
        ],
      );
      await c.read(forgeRateLimitProvider('/repo').future);
      await c.read(forgeProvider('/repo').future);
      expect(git.calls.where((a) => a.contains('http.proxy')), isEmpty);
    });

    test('update checks go through the proxy', () async {
      final c = _container(
        _FakeGit((_) => const GitResult(1, '', '')),
        settings: AppSettings(
          updateConsent: 'on',
          proxyMode: 'manual',
          proxyUrl: 'http://127.0.0.1:${proxy.port}',
        ),
      );
      await c.read(updateStatusProvider.notifier).check(manual: true);
      expect(c.read(updateStatusProvider), isA<UpdateFailed>());
      expect(seen.single.method, 'CONNECT');
    });

    test('tunnels https through the proxy rather than going direct', () async {
      final client = proxiedHttpClient(
        ProxyPolicy(gitProxy: '127.0.0.1:${proxy.port}'),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('https://mergelio.invalid/x')),
        throwsA(anything),
      );
      expect(seen.single.method, 'CONNECT');
      expect(seen.single.uri.toString(), contains('mergelio.invalid:443'));
    });
  });
}
