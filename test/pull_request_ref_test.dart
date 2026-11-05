import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/pull_request_ref.dart';

void main() {
  group('pullRequestHeadRef', () {
    test('github serves a pull request under refs/pull', () {
      expect(pullRequestHeadRef(ForgeKind.github, 12), 'refs/pull/12/head');
    });

    test('gitlab serves a merge request under refs/merge-requests', () {
      expect(
        pullRequestHeadRef(ForgeKind.gitlab, 3),
        'refs/merge-requests/3/head',
      );
    });

    test('refuses a number no forge hands out', () {
      expect(
        () => pullRequestHeadRef(ForgeKind.github, 0),
        throwsArgumentError,
      );
      expect(
        () => pullRequestHeadRef(ForgeKind.gitlab, -1),
        throwsArgumentError,
      );
    });
  });

  group('pullRequestLocalBranch', () {
    test('names a github pull request pr/<n>', () {
      expect(pullRequestLocalBranch(ForgeKind.github, 12), 'pr/12');
    });

    test('names a gitlab merge request mr/<n>', () {
      expect(pullRequestLocalBranch(ForgeKind.gitlab, 3), 'mr/3');
    });

    test('refuses a number no forge hands out', () {
      expect(
        () => pullRequestLocalBranch(ForgeKind.github, 0),
        throwsArgumentError,
      );
    });
  });

  group('pullRequestBaseRef', () {
    test('names the target branch under refs/heads', () {
      expect(pullRequestBaseRef('main'), 'refs/heads/main');
      expect(pullRequestBaseRef('release/1.x'), 'refs/heads/release/1.x');
    });

    test('refuses a name that would change what git is asked to do', () {
      // The name arrives from the forge and is handed to git fetch as a
      // refspec: a colon would add a destination and write a local ref, a
      // leading plus would force it, and the rest are names git itself
      // refuses, so nothing that works is lost.
      for (final bad in [
        '',
        'a:b',
        'refs/x:refs/heads/main',
        '+main',
        '-main',
        'a..b',
        'a b',
        'a~1',
        'a^',
        'a?',
        'a*',
        'a[1]',
        r'a\b',
        '/a',
        'a/',
        'a//b',
        'a.',
        '.a',
        'a/.b',
        'a.lock',
        'a@{1}',
        'a\x00b',
        'a\nb',
      ]) {
        expect(() => pullRequestBaseRef(bad), throwsArgumentError, reason: bad);
      }
    });
  });
}
