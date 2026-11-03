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
}
