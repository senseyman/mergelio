import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

PullRequest _pr({String source = 'feat/x', String target = 'main'}) =>
    PullRequest(
      number: 1,
      title: 't',
      state: PullRequestState.open,
      author: const ForgeUser(login: 'octocat'),
      sourceBranch: source,
      targetBranch: target,
      headSha: 'sha',
    );

void main() {
  group('forgeBranchLabel', () {
    test('names only the source when the target is the trunk', () {
      // Almost every request targets the trunk, so saying so on every row
      // spends the widest field in the line on nothing.
      expect(forgeBranchLabel(_pr(), 'main'), 'feat/x');
    });

    test('names both when the target is somewhere else', () {
      expect(
        forgeBranchLabel(_pr(target: 'release/2'), 'main'),
        'feat/x → release/2',
      );
    });

    test('names both when the trunk is unknown', () {
      // Better a redundant arrow than hiding the one case worth seeing.
      expect(forgeBranchLabel(_pr(), null), 'feat/x → main');
    });
  });

  group('forgeMetaLine', () {
    test('joins what it was given', () {
      expect(
        forgeMetaLine(['octocat', '2h', 'feat/x']),
        'octocat · 2h · feat/x',
      );
    });

    test('drops what the forge did not send, without leaving separators', () {
      expect(forgeMetaLine(['octocat', null, 'feat/x']), 'octocat · feat/x');
      expect(forgeMetaLine([null, '', 'feat/x']), 'feat/x');
      expect(forgeMetaLine([null, null]), isEmpty);
    });
  });
}
