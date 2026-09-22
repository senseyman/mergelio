import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
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

/// A [GitService] that records the body of every `git credential` command it
/// is given, so a test can assert which host a lookup actually named.
class _RecordingCredentialGitService implements GitService {
  final requests = <String>[];

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
    if (args.length >= 2 && args[0] == 'credential') {
      requests.add(stdin ?? '');
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

  group('forgeAccountTokenProvider', () {
    test('an account row reads the token for its own host', () async {
      final git = _RecordingCredentialGitService();
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          originRemoteUrlProvider('/repo')
              .overrideWith((ref) async => 'https://github.com/o/r.git'),
        ],
      );
      addTearDown(c.dispose);

      await c.read(
        forgeAccountTokenProvider((host: kGitlabHost, path: '/repo')).future,
      );

      // The lookup must name gitlab.com even while a GitHub repository is
      // open: a token is a fact about a host, not about the active tab.
      expect(git.requests.single, contains('host=gitlab.com'));
      expect(git.requests.single, contains('username=x-access-token'));
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

  group('forgeProvider', () {
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

      final forge = await c.read(forgeProvider('/repo').future);

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

      expect(await c.read(forgeProvider('/repo').future), isNull);
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

      final forge = await c.read(forgeProvider('/repo').future);
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

      final forge = await c.read(forgeProvider('/repo').future);
      await forge!.pullRequests();

      expect(sentAuth, isNull);
    });

    test('a gitlab remote builds a gitlab forge', () async {
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(_StubCredentialGitService()),
          originRemoteUrlProvider('/repo')
              .overrideWith((ref) async => 'git@gitlab.com:group/sub/app.git'),
        ],
      );
      addTearDown(c.dispose);

      final forge = await c.read(forgeProvider('/repo').future);

      expect(forge, isA<GitlabForge>());
      expect(forge!.host.kind, ForgeKind.gitlab);
      expect(forge.host.projectPath, 'group/sub/app');
    });

    test('a github remote still builds a github forge', () async {
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(_StubCredentialGitService()),
          originRemoteUrlProvider('/repo')
              .overrideWith((ref) async => 'https://github.com/o/r.git'),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(forgeProvider('/repo').future), isA<GitHubForge>());
    });
  });

  group('forgeRateLimitProvider', () {
    test('reads the budget from a well-formed response', () async {
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          forgeHttpClientProvider.overrideWithValue(
            MockClient(
              (req) async => http.Response(
                jsonEncode({
                  'resources': {
                    'core': {'limit': 60, 'remaining': 42},
                  },
                }),
                200,
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);

      final limit = await c.read(forgeRateLimitProvider('/repo').future);

      expect(limit, isNotNull);
      expect(limit!.limit, 60);
      expect(limit.remaining, 42);
    });

    test(
      'a response that cannot be read yields null, not a thrown error',
      () async {
        // A failing budget read is a courtesy going unmet, not an error the
        // rest of the panel should ever see.
        final c = ProviderContainer(
          overrides: [
            originRemoteUrlProvider.overrideWith(
              (ref, path) async => 'https://github.com/o/r.git',
            ),
            forgeTokenProvider.overrideWith((ref, path) async => null),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((req) async => http.Response('not json', 500)),
            ),
          ],
        );
        addTearDown(c.dispose);

        expect(await c.read(forgeRateLimitProvider('/repo').future), isNull);
      },
    );

    test('a gitlab repository reports no request budget', () async {
      // GitLab has no free budget endpoint, and guessing one from response
      // headers would put mutable per-host state inside the transport.
      // Absent is the honest answer, and the row shows nothing rather than
      // a zero.
      final c = ProviderContainer(
        overrides: [
          gitServiceProvider.overrideWithValue(_StubCredentialGitService()),
          originRemoteUrlProvider('/repo')
              .overrideWith((ref) async => 'https://gitlab.com/group/app.git'),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(forgeRateLimitProvider('/repo').future), isNull);
    });

    test('closes its http client once the single call is done', () async {
      final client = _TrackingClient(
        MockClient((req) async => http.Response('not json', 500)),
      );
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          forgeHttpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(c.dispose);

      // Deliberately not awaiting container disposal here: unlike
      // [forgeProvider], nothing keeps this client alive between
      // requests, so it must already be closed once the one call this
      // provider ever makes has returned — even though the response itself
      // could not be read as a rate limit.
      await c.read(forgeRateLimitProvider('/repo').future);

      expect(client.closed, isTrue);
    });
  });

  group('client lifetime', () {
    test('forgeProvider closes its http client once nothing watches it '
        'any more', () async {
      final client = _TrackingClient(
        MockClient((req) async => http.Response('[]', 200)),
      );
      final c = ProviderContainer(
        overrides: [
          originRemoteUrlProvider.overrideWith(
            (ref, path) async => 'https://github.com/o/r.git',
          ),
          forgeTokenProvider.overrideWith((ref, path) async => null),
          forgeHttpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(c.dispose);

      final forge = await c.read(forgeProvider('/repo').future);
      await forge!.pullRequests();
      expect(
        client.closed,
        isFalse,
        reason: 'still in use — closing here would break the next call',
      );

      c.dispose();

      expect(client.closed, isTrue);
    });
  });
}

/// Wraps [_inner] to record whether [close] was called, since neither
/// [http.Client] nor [MockClient] exposes that on its own.
class _TrackingClient extends http.BaseClient {
  final http.Client _inner;
  bool closed = false;

  _TrackingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
