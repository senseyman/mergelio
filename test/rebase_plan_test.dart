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
      expect(todo, contains(r"'it'\''s new'"));
    });

    test('a multi-line reword message stays on one todo line', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.reword, message: 'sub\n\nbody'),
      ]);
      // A todo file is line-oriented: a literal newline inside the exec line
      // would be read as a separate (invalid) instruction.
      final lines = todo.trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines.first, 'pick aaa');
      expect(lines.last, startsWith('exec '));
      expect(lines.last, contains(r'sub\n\nbody'));
    });

    test('backslashes in a reword message survive escaping', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.reword, message: r'path\to\thing'),
      ]);
      expect(todo.trim().split('\n'), hasLength(2));
      expect(todo, contains(r'path\\to\\thing'));
    });

    test('a signed reword asks git to re-sign the rewritten commit', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.reword, message: 'x', sign: true),
      ]);
      expect(todo, contains('git commit --amend -S -F -'));
    });

    test('an unsigned reword never passes -S', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.reword, message: 'x'),
      ]);
      expect(todo, isNot(contains('-S')));
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

  group('applyPreset', () {
    final steps = [
      const RebaseStep('aaa', RebaseAction.pick, message: 'first'),
      const RebaseStep('bbb', RebaseAction.pick, message: 'second'),
      const RebaseStep('ccc', RebaseAction.pick, message: 'third'),
    ];

    test('asIs picks every commit in the original order', () {
      final out = applyPreset(steps, RebasePreset.asIs);
      expect(out.map((s) => s.sha), ['aaa', 'bbb', 'ccc']);
      expect(out.every((s) => s.action == RebaseAction.pick), isTrue);
    });

    test('squashAll keeps the first commit and squashes the rest', () {
      final out = applyPreset(steps, RebasePreset.squashAll);
      expect(out.map((s) => s.action), [
        RebaseAction.pick,
        RebaseAction.squash,
        RebaseAction.squash,
      ]);
      expect(buildRebaseTodo(out), 'pick aaa\nsquash bbb\nsquash ccc\n');
    });

    test('squashKeepFirst fixups the rest so only the first message lives', () {
      final out = applyPreset(steps, RebasePreset.squashKeepFirst);
      expect(out.map((s) => s.action), [
        RebaseAction.pick,
        RebaseAction.fixup,
        RebaseAction.fixup,
      ]);
    });

    test('messages and shas survive every preset', () {
      for (final p in RebasePreset.values) {
        final out = applyPreset(steps, p);
        expect(out.map((s) => s.sha), ['aaa', 'bbb', 'ccc']);
        expect(out.map((s) => s.message), ['first', 'second', 'third']);
      }
    });

    test('a single commit is untouched by the squash presets', () {
      final one = [const RebaseStep('aaa', RebaseAction.pick)];
      for (final p in RebasePreset.values) {
        expect(applyPreset(one, p).single.action, RebaseAction.pick);
      }
    });

    test('an empty plan stays empty', () {
      for (final p in RebasePreset.values) {
        expect(applyPreset(const [], p), isEmpty);
      }
    });

    test('a preset overwrites any earlier per-commit edits', () {
      final edited = [
        const RebaseStep('aaa', RebaseAction.drop),
        const RebaseStep('bbb', RebaseAction.reword, message: 'x'),
      ];
      expect(applyPreset(edited, RebasePreset.asIs).map((s) => s.action), [
        RebaseAction.pick,
        RebaseAction.pick,
      ]);
    });
  });

  group('rebasePlanError', () {
    test('an all-pick plan is valid', () {
      expect(
        rebasePlanError([
          const RebaseStep('a', RebaseAction.pick),
          const RebaseStep('b', RebaseAction.pick),
        ]),
        isNull,
      );
    });

    test('squashing the first commit is rejected', () {
      // git: "Cannot 'squash' without a previous commit".
      expect(
        rebasePlanError([
          const RebaseStep('a', RebaseAction.squash),
          const RebaseStep('b', RebaseAction.fixup),
        ]),
        contains('first commit'),
      );
    });

    test('fixing up the first commit is rejected', () {
      expect(
        rebasePlanError([const RebaseStep('a', RebaseAction.fixup)]),
        isNotNull,
      );
    });

    test('a squash below a dropped first commit is rejected', () {
      // Dropping the commit above leaves nothing to merge into either.
      expect(
        rebasePlanError([
          const RebaseStep('a', RebaseAction.drop),
          const RebaseStep('b', RebaseAction.squash),
        ]),
        isNotNull,
      );
    });

    test('a squash under a kept commit is fine', () {
      expect(
        rebasePlanError([
          const RebaseStep('a', RebaseAction.pick),
          const RebaseStep('b', RebaseAction.squash),
        ]),
        isNull,
      );
    });

    test('every preset produces a valid plan', () {
      final steps = [
        const RebaseStep('a', RebaseAction.pick),
        const RebaseStep('b', RebaseAction.pick),
      ];
      for (final p in RebasePreset.values) {
        expect(rebasePlanError(applyPreset(steps, p)), isNull);
      }
    });

    test('an empty plan is valid', () {
      expect(rebasePlanError(const []), isNull);
    });
  });
}
