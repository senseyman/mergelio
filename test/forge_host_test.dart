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

    test('refuses a remote whose path walks up out of the project', () {
      // owner and repo are spliced straight into an API path, and Uri
      // resolves a `.` or `..` segment away rather than sending it, so a
      // remote carrying one addresses a different project under this user's
      // token. No real remote carries one.
      //
      // A scheme URL is normalised by Uri before it is ever split, which
      // disposes of the obvious spellings on its own. The two that survive
      // are an scp-style remote, which never goes through Uri at all, and a
      // repository named so that stripping `.git` leaves `..` behind.
      for (final url in [
        'https://github.com/owner/...git',
        'git@github.com:../evil.git',
        'git@github.com:./evil.git',
        'git@gitlab.com:group/../evil/repo.git',
        'git@gitlab.com:group/./repo.git',
        'git@gitlab.com:group/...git',
      ]) {
        expect(resolveForgeHost(url), isNull, reason: url);
      }
    });

    test('a scheme URL with dot segments never reaches the splitter', () {
      // Uri normalises these away, which is why the list above does not
      // repeat them. Pinned so a later move off Uri cannot quietly reopen the
      // hole.
      expect(resolveForgeHost('https://github.com/../evil.git'), isNull);
      expect(resolveForgeHost('ssh://git@github.com/../evil.git'), isNull);
      expect(
        resolveForgeHost('https://gitlab.com/group/../evil/repo.git')?.owner,
        'evil',
      );
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
