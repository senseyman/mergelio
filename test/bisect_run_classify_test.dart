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

    test('a dirty tree outranks a message git does spell out', () {
      // What git really says when a command dirties a tracked file and then
      // cannot be run: it reports the verification it could not do, not the
      // change that stopped it. The dirty tree is the more direct answer.
      expect(
        classifyBisectRun(
          1,
          "error: unable to verify '/bin/sh' '-c' './nope.sh' on 'good' revision",
          treeDirty: true,
        ),
        BisectRunOutcome.treeDirtied,
      );
    });

    test('a bogus exit code means the command could not run', () {
      expect(
        classifyBisectRun(
          1,
          "error: bogus exit code 127 for 'good' revision",
          treeDirty: false,
        ),
        BisectRunOutcome.commandUnrunnable,
      );
    });

    test('a run that cannot continue means every candidate was skipped', () {
      // git's own "We cannot bisect more!" goes to stdout, so this — the whole
      // of what it puts on stderr — is all the classifier gets to read.
      expect(
        classifyBisectRun(
          2,
          'error: bisect run cannot continue any more',
          treeDirty: false,
        ),
        BisectRunOutcome.exhausted,
      );
    });

    test('the stdout-only exhaustion notice is not read from stderr', () {
      // A guard against keying on the wrong stream again: on its own this
      // string never reaches stderr, and a classifier that matched it would
      // have let the real exhaustion above go by as a plain failure.
      expect(
        classifyBisectRun(2, 'We cannot bisect more!', treeDirty: false),
        BisectRunOutcome.failed,
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
