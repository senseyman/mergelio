import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';

void main() {
  const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const nb = '1111111111111111111111111111111111111111';

  group('interruptedPick', () {
    test('a pick git started but never committed comes back', () {
      expect(
        interruptedPick('pick $a # one\npick $b # two\n', '$a $nb\n'),
        'pick $b # two',
      );
    });

    test('the first pick, before anything was rewritten', () {
      expect(interruptedPick('pick $a # one\n', ''), 'pick $a # one');
    });

    test('a pick that landed is not picked twice', () {
      expect(interruptedPick('pick $a # one\n', '$a $nb\n'), isNull);
    });

    test('short forms and the other committing verbs count', () {
      expect(interruptedPick('p $a\n', ''), 'p $a');
      expect(interruptedPick('reword $a # x\n', ''), 'reword $a # x');
      expect(interruptedPick('edit $a\n', ''), 'edit $a');
    });

    test('a short sha is matched against the full one git records', () {
      expect(interruptedPick('pick aaaaaaa # one\n', '$a $nb\n'), isNull);
    });

    test('squash and fixup are left alone', () {
      // Their message is built up across steps in state files of git's own,
      // so replaying one could fold its message in twice.
      expect(interruptedPick('pick $a\nsquash $b\n', '$a $nb\n'), isNull);
      expect(interruptedPick('pick $a\nfixup -C $b\n', '$a $nb\n'), isNull);
    });

    test('steps that commit nothing of their own are left alone', () {
      for (final last in [
        'exec make test',
        'break',
        'label onto',
        'reset onto',
        'update-ref refs/heads/x',
        'merge -C $b topic',
      ]) {
        expect(interruptedPick('pick $a\n$last\n', '$a $nb\n'), isNull);
      }
    });

    test('an empty or comment-only list has nothing to bring back', () {
      expect(interruptedPick('', ''), isNull);
      expect(interruptedPick('# nothing\n', ''), isNull);
    });
  });
}
