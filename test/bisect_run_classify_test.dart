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
      // string never reaches stderr, so reading it as exhaustion would label
      // an exit code git never uses for exhaustion as one. Paired with exit 1,
      // which git does use for several unrelated failures.
      expect(
        classifyBisectRun(1, 'We cannot bisect more!', treeDirty: false),
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

    test('exhaustion is read off the exit code, not off English', () {
      // Measured against git 2.55.0, whose exit 2 from `bisect run` is its own
      // "only skipped commits left" and nothing else: every other failure
      // measured came back 1, 56 or 128. The stderr below is what the same
      // command really printed under uk_UA.UTF-8 and fr_FR.UTF-8, and
      // Mergelio ships Ukrainian, so keying on the English sentence alone
      // reports a normal ending as an unexplained failure for those users.
      expect(
        classifyBisectRun(
          2,
          'помилка: неможливо продовжити бісекцію',
          treeDirty: false,
        ),
        BisectRunOutcome.exhausted,
      );
      expect(
        classifyBisectRun(
          2,
          'erreur : la bissection ne peut plus continuer',
          treeDirty: false,
        ),
        BisectRunOutcome.exhausted,
      );
    });

    test('a dirty tree still outranks the code that means exhaustion', () {
      // Ordering guard, in a locale that gives the messages no say at all.
      expect(
        classifyBisectRun(
          2,
          'помилка: неможливо продовжити бісекцію',
          treeDirty: true,
        ),
        BisectRunOutcome.treeDirtied,
      );
    });

    test('an exit code git does not use for exhaustion is not exhaustion', () {
      // 3 and 4 are git's own merge-base and nesting failures; neither is a
      // hunt that ran out of candidates.
      expect(
        classifyBisectRun(3, 'fatal: unrelated', treeDirty: false),
        BisectRunOutcome.failed,
      );
      expect(
        classifyBisectRun(4, 'fatal: unrelated', treeDirty: false),
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
