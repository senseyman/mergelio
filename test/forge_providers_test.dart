import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/github_forge.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/state/forge.dart';

void main() {
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
  });
}
