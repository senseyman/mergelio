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
        'remote: Counting objects: 100% (5/5), done.\n'
        'error: failed to push some refs',
      ),
      'error: failed to push some refs',
    );
  });

  test("the server's own error wins over git's summary", () {
    expect(
      gitErrorLine(
        '\n  \nremote: Enumerating objects: 5\n'
        'remote: error: GH006: Protected branch update failed for '
        'refs/heads/main.\n'
        'error: failed to push some refs',
      ),
      'error: GH006: Protected branch update failed for refs/heads/main.',
    );
  });

  test('the first of several server errors is kept', () {
    expect(
      gitErrorLine(
        'remote: error: GH001: Large files detected.\n'
        'remote: error: GH006: Protected branch update failed for '
        'refs/heads/main.\n'
        ' ! [remote rejected] main -> main (pre-receive hook declined)',
      ),
      'error: GH001: Large files detected.',
    );
  });

  test('a fatal from the server counts as its error', () {
    expect(
      gitErrorLine(
        'To github.com:o/r.git\n'
        'remote: fatal: repository is archived  \n'
        "error: failed to push some refs to 'github.com:o/r.git'",
      ),
      'fatal: repository is archived',
    );
  });

  test('a failed clone skips the line naming its directory', () {
    expect(
      gitErrorLine(
        "Cloning into 'repo'...\n"
        "fatal: unable to access 'https://host/o/r.git/': "
        'Could not resolve host: host',
      ),
      "fatal: unable to access 'https://host/o/r.git/': "
      'Could not resolve host: host',
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
