import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';

const _author = ForgeUser(login: 'octocat');

CheckRun _run(String name, CheckState state) =>
    CheckRun(name: name, state: state);

void main() {
  group('ChecksSummary.from', () {
    test('no runs at all means the forge reported no CI', () {
      expect(ChecksSummary.from(const []).overall, ChecksOverall.none);
    });

    test('every run succeeding is a success', () {
      final s = ChecksSummary.from([
        _run('build', CheckState.success),
        _run('test', CheckState.success),
      ]);
      expect(s.overall, ChecksOverall.success);
      expect(s.runs, hasLength(2));
    });

    test('any failure outranks a success', () {
      final s = ChecksSummary.from([
        _run('build', CheckState.success),
        _run('test', CheckState.failure),
      ]);
      expect(s.overall, ChecksOverall.failure);
    });

    test('a failure outranks a run still in progress', () {
      // A red build is actionable now; waiting for the rest does not change
      // that, so the summary must not read as merely "running".
      final s = ChecksSummary.from([
        _run('build', CheckState.running),
        _run('test', CheckState.failure),
      ]);
      expect(s.overall, ChecksOverall.failure);
    });

    test('anything still running, with nothing failed, is running', () {
      final s = ChecksSummary.from([
        _run('build', CheckState.success),
        _run('test', CheckState.queued),
      ]);
      expect(s.overall, ChecksOverall.running);
    });

    test('skipped and cancelled runs alone are mixed, not success', () {
      final s = ChecksSummary.from([
        _run('build', CheckState.success),
        _run('lint', CheckState.skipped),
      ]);
      expect(s.overall, ChecksOverall.mixed);
    });

    test('an unknown state never reads as success', () {
      // A forge adding a state we do not know must not be reported green.
      final s = ChecksSummary.from([
        _run('build', CheckState.success),
        _run('mystery', CheckState.unknown),
      ]);
      expect(s.overall, ChecksOverall.mixed);
    });
  });

  group('models', () {
    test('a pull request compares by value', () {
      const a = PullRequest(
        number: 7,
        title: 'Fix the thing',
        state: PullRequestState.open,
        author: _author,
        sourceBranch: 'fix/thing',
        targetBranch: 'main',
        headSha: 'abc123',
      );
      const b = PullRequest(
        number: 7,
        title: 'Fix the thing',
        state: PullRequestState.open,
        author: _author,
        sourceBranch: 'fix/thing',
        targetBranch: 'main',
        headSha: 'abc123',
      );
      expect(a, b);
    });

    test('a user falls back to its login when no display name is given', () {
      const u = ForgeUser(login: 'octocat');
      expect(u.displayName, isEmpty);
      expect(u.shown, 'octocat');
      expect(
        const ForgeUser(login: 'octocat', displayName: 'Mona').shown,
        'Mona',
      );
    });

    test('an issue carries labels and defaults them to empty', () {
      const i = Issue(
        number: 12,
        title: 'Crash on open',
        state: IssueState.open,
        author: _author,
      );
      expect(i.labels, isEmpty);
    });
  });
}
