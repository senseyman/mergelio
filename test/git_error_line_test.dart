// The line of git's stderr that a short failure notification shows.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/op_clock.dart';

void main() {
  test('a rejected push skips the destination line', () {
    expect(
      gitErrorLine(
        'To github.com:o/r.git\n'
        ' ! [rejected]        main -> main (fetch first)\n'
        "error: failed to push some refs to 'github.com:o/r.git'\n"
        'hint: Updates were rejected because the remote contains work',
      ),
      '! [rejected]        main -> main (fetch first)',
    );
  });

  test('a first line that says why is kept', () {
    expect(
      gitErrorLine(
        'git@github.com: Permission denied (publickey).\n'
        'fatal: Could not read from remote repository.',
      ),
      'git@github.com: Permission denied (publickey).',
    );
  });

  test('a pull skips the source line and ref summaries', () {
    expect(
      gitErrorLine(
        'From github.com:o/r\n'
        ' * branch            main       -> FETCH_HEAD\n'
        ' = [up to date]      dev        -> origin/dev\n'
        'fatal: Not possible to fast-forward, aborting.',
      ),
      'fatal: Not possible to fast-forward, aborting.',
    );
  });

  test('remote chatter and blank lines are skipped', () {
    expect(
      gitErrorLine(
        '\n  \nremote: Enumerating objects: 5\n'
        'remote: error: GH006: Protected branch update failed\n'
        'error: failed to push some refs',
      ),
      'error: failed to push some refs',
    );
  });

  test('only filtered lines falls back to the first non-empty one', () {
    expect(gitErrorLine('hint: x'), 'hint: x');
    expect(gitErrorLine('\n  \n  hint: x\nremote: y'), 'hint: x');
  });

  test('nothing to say gives an empty line', () {
    expect(gitErrorLine(''), '');
    expect(gitErrorLine('\n   \n'), '');
  });
}
