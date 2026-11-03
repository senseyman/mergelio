import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/forge_server.dart';

void main() {
  const ghe = ForgeServer(kind: ForgeKind.github, host: 'ghe.corp.example');
  const ghePorted = ForgeServer(
    kind: ForgeKind.github,
    host: 'ghe.corp.example',
    port: 8443,
  );
  const selfGitlab = ForgeServer(kind: ForgeKind.gitlab, host: 'git.corp');

  group('ForgeServer urls', () {
    test('github.com keeps its separate api host', () {
      expect(
        kGithubCloud.api('/repos/o/r/pulls', {'state': 'open'}).toString(),
        'https://api.github.com/repos/o/r/pulls?state=open',
      );
      expect(kGithubCloud.web('/o/r').toString(), 'https://github.com/o/r');
      expect(kGithubCloud.credentialHost, 'github.com');
      expect(kGithubCloud.isCloud, isTrue);
    });

    test('gitlab.com serves its api under /api/v4', () {
      expect(
        kGitlabCloud.api('/user').toString(),
        'https://gitlab.com/api/v4/user',
      );
      expect(kGitlabCloud.credentialHost, 'gitlab.com');
      expect(kGitlabCloud.isCloud, isTrue);
    });

    test('github enterprise serves its api under /api/v3 on its own host', () {
      expect(
        ghe.api('/repos/o/r').toString(),
        'https://ghe.corp.example/api/v3/repos/o/r',
      );
      expect(ghe.web('/o/r').toString(), 'https://ghe.corp.example/o/r');
      expect(ghe.isCloud, isFalse);
    });

    test('a port reaches the api, the web and the stored credential', () {
      expect(
        ghePorted.api('/user').toString(),
        'https://ghe.corp.example:8443/api/v3/user',
      );
      expect(
        ghePorted.web('/o/r').toString(),
        'https://ghe.corp.example:8443/o/r',
      );
      expect(ghePorted.credentialHost, 'ghe.corp.example:8443');
    });

    test('self-managed gitlab serves its api under /api/v4', () {
      expect(selfGitlab.apiBase, 'https://git.corp/api/v4');
    });

    test('compares by value', () {
      expect(
        const ForgeServer(kind: ForgeKind.github, host: 'ghe.corp.example'),
        ghe,
      );
      expect(ghe, isNot(ghePorted));
      expect(
        ghe,
        isNot(
          const ForgeServer(kind: ForgeKind.gitlab, host: 'ghe.corp.example'),
        ),
      );
    });

    test('round-trips through its settings key', () {
      for (final s in [
        kGithubCloud,
        kGitlabCloud,
        ghe,
        ghePorted,
        selfGitlab,
      ]) {
        expect(ForgeServer.fromKey(s.key, s.kind.name), s, reason: s.key);
      }
      expect(ForgeServer.fromKey('ghe.corp.example', 'svn'), isNull);
      expect(
        ForgeServer.fromKey('ghe.corp.example:notaport', 'github'),
        isNull,
      );
      expect(ForgeServer.fromKey('', 'github'), isNull);
      // A key that only parses once normalised is not one this version
      // wrote, and removing it by the normalised key would never find it.
      expect(ForgeServer.fromKey('GHE.corp.example', 'github'), isNull);
      expect(ForgeServer.fromKey('https://ghe.corp.example', 'github'), isNull);
    });
  });

  group('parseForgeServerUrl', () {
    ForgeServer? ok(String s, [ForgeKind k = ForgeKind.github]) =>
        parseForgeServerUrl(s, k).server;
    ForgeServerUrlProblem? problem(
      String s, [
      ForgeKind k = ForgeKind.github,
    ]) => parseForgeServerUrl(s, k).problem;

    test('reads an https url', () {
      expect(ok('https://ghe.corp.example'), ghe);
      expect(ok('https://ghe.corp.example/'), ghe);
      expect(ok('  https://GHE.Corp.Example/  '), ghe);
    });

    test('a bare host means https', () {
      expect(ok('ghe.corp.example'), ghe);
      expect(ok('ghe.corp.example:8443'), ghePorted);
    });

    test('the default https port is the same server', () {
      expect(ok('https://ghe.corp.example:443'), ghe);
    });

    test('refuses plain http, since the token would travel in the clear', () {
      expect(
        problem('http://ghe.corp.example'),
        ForgeServerUrlProblem.notHttps,
      );
      expect(ok('http://ghe.corp.example'), isNull);
    });

    test('refuses an install under a sub-path', () {
      expect(
        problem('https://corp.example/gitlab', ForgeKind.gitlab),
        ForgeServerUrlProblem.hasPath,
      );
    });

    test('refuses credentials, queries and fragments in the url', () {
      for (final s in [
        'https://me:secret@ghe.corp.example',
        'https://ghe.corp.example/?a=1',
        'https://ghe.corp.example/#x',
      ]) {
        expect(problem(s), ForgeServerUrlProblem.invalid, reason: s);
      }
    });

    test('refuses what is not a url at all', () {
      for (final s in ['', '   ', 'not a host', 'https://', 'ftp://x.y']) {
        expect(ok(s), isNull, reason: s);
      }
    });

    test('the public cloud is its own account, not a self-hosted one', () {
      expect(
        problem('https://github.com', ForgeKind.github),
        ForgeServerUrlProblem.isCloud,
      );
      expect(
        problem('www.gitlab.com', ForgeKind.gitlab),
        ForgeServerUrlProblem.isCloud,
      );
      expect(
        problem('api.github.com', ForgeKind.github),
        ForgeServerUrlProblem.isCloud,
      );
    });

    test('refuses a port no server can listen on', () {
      for (final s in [
        'https://x.corp:0',
        'https://x.corp:65536',
        'x.corp:99999',
      ]) {
        expect(problem(s), ForgeServerUrlProblem.invalid, reason: s);
      }
      expect(ok('x.corp:65535')?.port, 65535);
    });

    test('keeps the forge it was asked for', () {
      expect(ok('git.corp', ForgeKind.gitlab), selfGitlab);
    });
  });

  group('resolveForgeHost with registered servers', () {
    test('an unregistered host is still unknown', () {
      expect(resolveForgeHost('git@ghe.corp.example:o/r.git'), isNull);
    });

    test('a registered github enterprise host resolves', () {
      final h = resolveForgeHost(
        'git@ghe.corp.example:o/r.git',
        servers: const [ghe],
      );
      expect(h?.kind, ForgeKind.github);
      expect(h?.server, ghe);
      expect(h?.projectPath, 'o/r');
    });

    test('the server keeps its own port, whatever the remote used', () {
      // ssh on 2222 for git, https on 8443 for the api.
      final h = resolveForgeHost(
        'ssh://git@ghe.corp.example:2222/o/r.git',
        servers: const [ghePorted],
      );
      expect(h?.server, ghePorted);
    });

    test('matches the host case-insensitively', () {
      expect(
        resolveForgeHost(
          'https://GHE.corp.example/o/r',
          servers: const [ghe],
        )?.server,
        ghe,
      );
    });

    test('a self-managed gitlab keeps nested groups', () {
      final h = resolveForgeHost(
        'https://git.corp/a/b/c/app.git',
        servers: const [selfGitlab],
      );
      expect(h?.kind, ForgeKind.gitlab);
      expect(h?.owner, 'a/b/c');
      expect(h?.repo, 'app');
    });

    test('github enterprise still wants exactly owner/repo', () {
      expect(
        resolveForgeHost(
          'https://ghe.corp.example/o/r/tree/main',
          servers: const [ghe],
        ),
        isNull,
      );
    });

    test('the clouds resolve with or without a registry', () {
      expect(
        resolveForgeHost('git@github.com:o/r', servers: const [ghe])?.server,
        kGithubCloud,
      );
      expect(resolveForgeHost('git@gitlab.com:o/r')?.server, kGitlabCloud);
    });
  });
}
