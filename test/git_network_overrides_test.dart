import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_network_overrides.dart';
import 'package:mergelio/domain/git/git_service.dart';

import 'support/hermetic_git.dart';

class _Recorder implements GitService, GitBytesRunner {
  final List<Map<String, String>?> envs = [];
  int bytesCalls = 0;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    envs.add(environment);
    return const GitResult(0, '', '');
  }

  @override
  Future<Uint8List?> runBytes(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    required int maxBytes,
  }) async {
    bytesCalls++;
    return Uint8List(0);
  }

  @override
  Future<String> version() async => 'git version 2.50.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _proxy = GitNetworkOverrides(
  config: {'http.proxy': 'http://p:1'},
  env: {'NO_PROXY': ''},
);

void main() {
  group('GitNetworkOverrides.applyTo', () {
    test('adds config through the environment, not the command line', () {
      final env = _proxy.applyTo({'A': 'b'}, inherited: const {});
      expect(env, {
        'A': 'b',
        'NO_PROXY': '',
        'GIT_CONFIG_COUNT': '1',
        'GIT_CONFIG_KEY_0': 'http.proxy',
        'GIT_CONFIG_VALUE_0': 'http://p:1',
      });
    });

    test('appends after config the app inherited', () {
      final env = _proxy.applyTo(
        const {},
        inherited: {
          'GIT_CONFIG_COUNT': '2',
          'GIT_CONFIG_KEY_0': 'a.b',
          'GIT_CONFIG_VALUE_0': '1',
        },
      );
      expect(env['GIT_CONFIG_COUNT'], '3');
      expect(env['GIT_CONFIG_KEY_2'], 'http.proxy');
      expect(env.containsKey('GIT_CONFIG_KEY_0'), isFalse);
    });

    test(
      'appends after config the caller passed, which wins over inherited',
      () {
        final env = _proxy.applyTo(
          const {'GIT_CONFIG_COUNT': '1'},
          inherited: const {'GIT_CONFIG_COUNT': '5'},
        );
        expect(env['GIT_CONFIG_COUNT'], '2');
        expect(env['GIT_CONFIG_KEY_1'], 'http.proxy');
      },
    );

    test('an unreadable count starts from zero', () {
      final env = _proxy.applyTo(
        const {},
        inherited: const {'GIT_CONFIG_COUNT': 'x'},
      );
      expect(env['GIT_CONFIG_COUNT'], '1');
    });
  });

  group('NetworkEnvGitService', () {
    test(
      'adds the overrides to every command, keeping what it was given',
      () async {
        // Not only fetch and push reach the network: a checkout downloads LFS
        // objects through git-lfs's smudge filter, which inherits this
        // environment. http.proxy means nothing to a command that does not.
        final inner = _Recorder();
        final git = NetworkEnvGitService(inner, () => _proxy);
        await git.run(['checkout', 'main']);
        await git.run(['fetch'], environment: networkEnv());
        expect(inner.envs.first!['GIT_CONFIG_VALUE_0'], 'http://p:1');
        expect(inner.envs.last!['GIT_CONFIG_VALUE_0'], 'http://p:1');
        expect(inner.envs.last!['GIT_TERMINAL_PROMPT'], '0');
      },
    );

    test('with no overrides the environment is passed through as is', () async {
      final inner = _Recorder();
      final git = NetworkEnvGitService(inner, () => GitNetworkOverrides.none);
      await git.run(['status']);
      expect(inner.envs.single, isNull);
    });

    test(
      'reads the overrides at each call, so a change applies next time',
      () async {
        final inner = _Recorder();
        var current = GitNetworkOverrides.none;
        final git = NetworkEnvGitService(inner, () => current);
        await git.run(['fetch'], environment: networkEnv());
        current = _proxy;
        await git.run(['fetch'], environment: networkEnv());
        expect(inner.envs.first!.containsKey('GIT_CONFIG_COUNT'), isFalse);
        expect(inner.envs.last!['GIT_CONFIG_KEY_0'], 'http.proxy');
      },
    );

    test('still hands out raw bytes', () async {
      final inner = _Recorder();
      final GitService git = NetworkEnvGitService(inner, () => _proxy);
      await (git as GitBytesRunner).runBytes(['cat-file'], maxBytes: 1);
      expect(inner.bytesCalls, 1);
    });

    test('real git reads the injected value back', () async {
      final git = NetworkEnvGitService(const HermeticGit(), () => _proxy);
      final r = await git.run([
        'config',
        '--get',
        'http.proxy',
      ], environment: networkEnv());
      expect(r.out, 'http://p:1');
    });
  });
}
