import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/forge.dart';

/// A [GitService] that fails every command, so a repository backed by it
/// behaves like one whose git toolchain is unusable — no real process, no
/// filesystem, just an exception on the way out.
class _ThrowingGitService implements GitService {
  @override
  Future<String> version() async => 'git version 0.0.0';

  @override
  Future<bool> isRepository(String path) async => true;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    throw GitException('git is unavailable in this test');
  }
}

/// A [GitService] that answers `git credential fill` the way a helper that
/// already holds a token would, without touching a real git binary or a
/// filesystem — everything it returns is canned.
class _StubCredentialGitService implements GitService {
  @override
  Future<String> version() async => 'git version 0.0.0';

  @override
  Future<bool> isRepository(String path) async => true;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.length >= 2 && args[0] == 'credential' && args[1] == 'fill') {
      return const GitResult(0, 'password=stub-token\n\n', '');
    }
    return const GitResult(1, '', 'unsupported in this stub');
  }
}

void main() {
  group('originRemoteUrlProvider', () {
    test('a repository that cannot answer resolves to empty', () async {
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(_ThrowingGitService()),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(originRemoteUrlProvider('/repo').future), '');
    });
  });

  group('forgeTokenProvider', () {
    test('reads the token the credential helper already holds', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          gitServiceProvider.overrideWithValue(_StubCredentialGitService()),
        ],
      );
      addTearDown(c.dispose);

      final token = await c.read(forgeTokenProvider('/repo').future);

      expect(token?.value, 'stub-token');
    });
  });

  group('forgeHostProvider', () {
    test('resolves a github remote into forge coordinates', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'git@github.com:senseyman/mergelio.git',
          ),
        ],
      );
      addTearDown(c.dispose);

      final host = await c.read(forgeHostProvider('/repo').future);

      expect(host, isNotNull);
      expect(host!.kind, ForgeKind.github);
      expect(host.owner, 'senseyman');
      expect(host.repo, 'mergelio');
    });

    test('a repository on no known forge resolves to null', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => '/srv/git/local.git',
          ),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(forgeHostProvider('/repo').future), isNull);
    });

    test('a repository with no origin resolves to null', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith((ref, path) async => ''),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(forgeHostProvider('/repo').future), isNull);
    });
  });

  group('githubForgeProvider', () {
    test('builds a forge for a github repository', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
        ],
      );
      addTearDown(c.dispose);

      final forge = await c.read(githubForgeProvider('/repo').future);

      expect(forge, isA<GitHubForge>());
      expect(forge!.host.owner, 'o');
    });

    test('builds nothing when the repository is not on a forge', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith((ref, path) async => ''),
          forgeTokenProvider.overrideWith((ref, path) async => null),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(githubForgeProvider('/repo').future), isNull);
    });

    test('one etag cache is shared for the whole session', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(
        identical(c.read(etagCacheProvider), c.read(etagCacheProvider)),
        isTrue,
      );
    });

    test('the resolved token reaches the request that goes out', () async {
      String? sentAuth;
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith(
            (ref, path) async => const ForgeToken('secret-token'),
          ),
          forgeHttpClientProvider.overrideWithValue(
            MockClient((req) async {
              sentAuth = req.headers['authorization'];
              return http.Response('[]', 200);
            }),
          ),
        ],
      );
      addTearDown(c.dispose);

      final forge = await c.read(githubForgeProvider('/repo').future);
      await forge!.pullRequests();

      expect(sentAuth, 'Bearer secret-token');
    });

    test('no token means no authorization header, not an empty one', () async {
      // An empty Authorization header is not the same as none: GitHub would
      // reject it outright rather than serving the anonymous budget.
      String? sentAuth = 'unset';
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          forgeHttpClientProvider.overrideWithValue(
            MockClient((req) async {
              sentAuth = req.headers['authorization'];
              return http.Response('[]', 200);
            }),
          ),
        ],
      );
      addTearDown(c.dispose);

      final forge = await c.read(githubForgeProvider('/repo').future);
      await forge!.pullRequests();

      expect(sentAuth, isNull);
    });
  });
}
