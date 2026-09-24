import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';

void main() {
  group('classifyBisectRun', () {
    test('a clean exit is a finished hunt', () {
      expect(
        classifyBisectRun(0, '', treeDirty: false),
        BisectRunOutcome.finished,
      );
    });

    test('a dirty tree outranks every other failure reading', () {
      // git blames `git bisect good` for this, never the real cause, so the
      // dirty tree is checked before the messages git does spell out.
      expect(
        classifyBisectRun(
          1,
          "error: bisect run failed: 'git bisect good' exited with error code -1",
          treeDirty: true,
        ),
        BisectRunOutcome.treeDirtied,
      );
    });

    test('a dirty tree outranks a bogus exit code message', () {
      // Even if stderr has a message we'd normally classify specially, a dirty
      // tree takes precedence because it explains the failure more directly.
      expect(
        classifyBisectRun(
          1,
          "error: bogus exit code 127 for 'good' revision [abc]",
          treeDirty: true,
        ),
        BisectRunOutcome.treeDirtied,
      );
    });

    test('a bogus exit code means the command could not run', () {
      expect(
        classifyBisectRun(
          1,
          "error: bogus exit code 127 for 'good' revision [abc]",
          treeDirty: false,
        ),
        BisectRunOutcome.commandUnrunnable,
      );
    });

    test('cannot-bisect-more means every candidate was skipped', () {
      expect(
        classifyBisectRun(
          2,
          'We cannot bisect more!\nerror: bisect run cannot continue any more',
          treeDirty: false,
        ),
        BisectRunOutcome.exhausted,
      );
    });

    test('an unrecognised failure is reported as itself, not guessed', () {
      // Surfacing git's own words is honest; a confident wrong label is not.
      expect(
        classifyBisectRun(
          1,
          'error: something else entirely',
          treeDirty: false,
        ),
        BisectRunOutcome.failed,
      );
    });

    test('the exit code alone never decides an unrunnable command', () {
      // Exit 1 is also used for unrelated git errors, so keying on the code
      // would mislabel them.
      expect(
        classifyBisectRun(
          1,
          'fatal: not a valid object name',
          treeDirty: false,
        ),
        BisectRunOutcome.failed,
      );
    });

    test('the exit code alone never decides exhaustion', () {
      expect(
        classifyBisectRun(2, 'fatal: unrelated', treeDirty: false),
        BisectRunOutcome.failed,
      );
    });

    test('a clean exit wins even if the tree is dirty', () {
      // A command that writes untracked files finishes normally; the run
      // succeeded and there is nothing to explain.
      expect(
        classifyBisectRun(0, '', treeDirty: true),
        BisectRunOutcome.finished,
      );
    });

    test('a negative exit code is not treated as success', () {
      // Negative exit codes are unusual and should not be treated as finished.
      expect(
        classifyBisectRun(-1, 'error: something', treeDirty: false),
        BisectRunOutcome.failed,
      );
    });
  });
}
