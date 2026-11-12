import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/remote_spec.dart';

void main() {
  group('remoteNameError', () {
    test('accepts ordinary names', () {
      expect(remoteNameError('upstream'), isNull);
      expect(remoteNameError('my-fork_2.0'), isNull);
    });

    test('rejects empty and blank names', () {
      expect(remoteNameError(''), isNotNull);
      expect(remoteNameError('   '), isNotNull);
    });

    test('rejects embedded whitespace', () {
      expect(remoteNameError('my fork'), isNotNull);
      expect(remoteNameError('fork\tb'), isNotNull);
    });

    test('rejects characters git forbids in ref names', () {
      for (final name in ['a~b', 'a^b', 'a:b', 'a?b', 'a*b', 'a[b', r'a\b']) {
        expect(remoteNameError(name), isNotNull, reason: name);
      }
    });

    test('rejects a leading dash so a name cannot be read as an option', () {
      expect(remoteNameError('--upload-pack=touch /tmp/pwn'), isNotNull);
    });

    test('rejects a name already taken by another remote', () {
      expect(remoteNameError('origin', existing: ['origin']), isNotNull);
    });

    test('allows an edited remote to keep its own name', () {
      expect(
        remoteNameError('origin', existing: ['origin'], current: 'origin'),
        isNull,
      );
    });
  });

  group('remoteUrlError', () {
    test('accepts https, ssh, scp-style and local paths', () {
      expect(remoteUrlError('https://example.com/a.git'), isNull);
      expect(remoteUrlError('ssh://git@example.com/a.git'), isNull);
      expect(remoteUrlError('git@example.com:owner/a.git'), isNull);
      expect(remoteUrlError('/srv/git/a.git'), isNull);
    });

    test('rejects empty and blank URLs', () {
      expect(remoteUrlError(''), isNotNull);
      expect(remoteUrlError('  '), isNotNull);
    });

    test('rejects embedded whitespace', () {
      expect(remoteUrlError('https://example.com/a b.git'), isNotNull);
    });

    test('rejects a leading dash so a URL cannot be read as an option', () {
      expect(remoteUrlError('--upload-pack=touch /tmp/pwn'), isNotNull);
    });
  });

  group('isSshRemoteUrl', () {
    test('ssh urls and scp-style remotes are ssh', () {
      for (final url in [
        'git@github.com:ethereum/go-ethereum.git',
        'github.com:o/r.git',
        'ssh://git@github.com/o/r.git',
        'SSH://host:2222/r',
        'git+ssh://host/r',
        'ssh+git://host/r',
        '  git@host:r  ',
      ]) {
        expect(isSshRemoteUrl(url), isTrue, reason: url);
      }
    });

    test('http, git protocol, files and local paths are not', () {
      for (final url in [
        'https://github.com/o/r.git',
        'http://host/r',
        'git://host/r',
        'file:///srv/r.git',
        '/srv/r.git',
        './r',
        '../other:dir',
        r'C:\repos\r',
        'C:/repos/r',
        '  https://h/r  ',
        '',
      ]) {
        expect(isSshRemoteUrl(url), isFalse, reason: url);
      }
    });
  });
}
