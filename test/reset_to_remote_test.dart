import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/workspace/repo_sidebar.dart';

void main() {
  group('canResetToRemote', () {
    test('true only for the current branch with an upstream', () {
      expect(
        canResetToRemote(
          const Branch(name: 'x', current: true, upstream: 'origin/x'),
        ),
        isTrue,
      );
    });

    test('false when the branch is not current', () {
      expect(
        canResetToRemote(
          const Branch(name: 'x', current: false, upstream: 'origin/x'),
        ),
        isFalse,
      );
    });

    test('false when the branch has no upstream', () {
      expect(canResetToRemote(const Branch(name: 'x', current: true)), isFalse);
    });
  });
}
