import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_host.dart';

void main() {
  group('resolveForgeHost', () {
    test('reads an https remote', () {
      final h = resolveForgeHost('https://github.com/owner/repo.git');
      expect(h?.kind, ForgeKind.github);
      expect(h?.host, 'github.com');
      expect(h?.owner, 'owner');
      expect(h?.repo, 'repo');
      expect(h?.projectPath, 'owner/repo');
    });

    test('accepts an https remote without the .git suffix', () {
      expect(resolveForgeHost('https://github.com/owner/repo')?.repo, 'repo');
    });

    test('accepts a trailing slash', () {
      expect(resolveForgeHost('https://gitlab.com/owner/repo/')?.repo, 'repo');
    });

    test('drops a userinfo prefix', () {
      final h = resolveForgeHost('https://user@github.com/owner/repo.git');
      expect(h?.host, 'github.com');
      expect(h?.owner, 'owner');
    });

    test('reads an ssh:// remote, with and without a port', () {
      expect(
        resolveForgeHost('ssh://git@github.com/owner/repo.git')?.projectPath,
        'owner/repo',
      );
      final ported = resolveForgeHost('ssh://git@github.com:22/owner/repo.git');
      expect(ported?.host, 'github.com');
      expect(ported?.projectPath, 'owner/repo');
    });

    test('reads an scp-style remote', () {
      final h = resolveForgeHost('git@github.com:owner/repo.git');
      expect(h?.kind, ForgeKind.github);
      expect(h?.host, 'github.com');
      expect(h?.projectPath, 'owner/repo');
    });

    test('keeps GitLab subgroups in the project path', () {
      final h = resolveForgeHost(
        'https://gitlab.com/group/sub/deeper/repo.git',
      );
      expect(h?.kind, ForgeKind.gitlab);
      expect(h?.owner, 'group/sub/deeper');
      expect(h?.repo, 'repo');
      expect(h?.projectPath, 'group/sub/deeper/repo');
    });

    test('keeps subgroups for an scp-style GitLab remote too', () {
      final h = resolveForgeHost('git@gitlab.com:group/sub/repo.git');
      expect(h?.projectPath, 'group/sub/repo');
    });

    test('treats a www host as the same forge', () {
      expect(
        resolveForgeHost('https://www.github.com/owner/repo')?.kind,
        ForgeKind.github,
      );
    });

    test('rejects a GitHub path that is not exactly owner/repo', () {
      // github.com has no subgroups, so extra segments mean this is a web URL
      // rather than a remote.
      expect(
        resolveForgeHost('https://github.com/owner/repo/tree/main'),
        isNull,
      );
      expect(resolveForgeHost('https://github.com/owner'), isNull);
    });

    test('returns null for hosts that are not a supported forge', () {
      expect(resolveForgeHost('https://bitbucket.org/owner/repo.git'), isNull);
      expect(resolveForgeHost('git@git.example.com:owner/repo.git'), isNull);
    });

    test('returns null for local and malformed remotes', () {
      for (final url in [
        '',
        '   ',
        '/Users/me/code/repo',
        '../sibling-repo',
        'file:///Users/me/code/repo',
        'https://gitlab.com/',
        'https://gitlab.com/onlyone',
        'not a url at all',
      ]) {
        expect(resolveForgeHost(url), isNull, reason: url);
      }
    });

    test('compares by value', () {
      expect(
        resolveForgeHost('https://github.com/owner/repo.git'),
        resolveForgeHost('git@github.com:owner/repo'),
      );
    });
  });
}
