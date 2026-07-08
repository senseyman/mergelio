import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';

void main() {
  group('buildRebaseTodo', () {
    test('picks in order', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.pick),
        const RebaseStep('bbb', RebaseAction.pick),
      ]);
      expect(todo, 'pick aaa\npick bbb\n');
    });

    test('reword becomes pick + exec amend with a quoted message', () {
      final todo = buildRebaseTodo([
        RebaseStep('aaa', RebaseAction.reword, message: "it's new"),
      ]);
      expect(todo, contains('pick aaa'));
      expect(todo, contains(r"exec git commit --amend -m 'it'\''s new'"));
    });

    test('squash and fixup map directly; drop is omitted', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.pick),
        const RebaseStep('bbb', RebaseAction.squash),
        const RebaseStep('ccc', RebaseAction.fixup),
        const RebaseStep('ddd', RebaseAction.drop),
      ]);
      expect(todo, 'pick aaa\nsquash bbb\nfixup ccc\n');
    });
  });

  group('isNoOpPlan', () {
    final orig = [
      const RebaseStep('a', RebaseAction.pick),
      const RebaseStep('b', RebaseAction.pick),
    ];

    test('unchanged pick order is a no-op', () {
      expect(isNoOpPlan(orig, orig), isTrue);
    });

    test('reorder is not a no-op', () {
      expect(isNoOpPlan(orig, [orig[1], orig[0]]), isFalse);
    });

    test('any non-pick action is not a no-op', () {
      expect(
        isNoOpPlan(orig, [orig[0], const RebaseStep('b', RebaseAction.squash)]),
        isFalse,
      );
    });
  });
}
