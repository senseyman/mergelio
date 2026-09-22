import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/gitlab_parse.dart';
import 'package:mergelio/domain/forge/models.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/forge/gitlab/$name').readAsStringSync());

void main() {
  group('parseMergeRequests', () {
    test('the number is the iid a person sees, never the global id', () {
      final prs = parseMergeRequests(fixture('merge_requests.json'));

      // GitLab's `id` addresses a different merge request in a different
      // project; a row built from it links somewhere else entirely.
      expect(prs.first.number, 42);
      expect(prs.map((p) => p.number), isNot(contains(900001)));
    });

    test('maps branches, head sha, author and time', () {
      final pr = parseMergeRequests(fixture('merge_requests.json')).first;

      expect(pr.title, 'Speed up graph');
      expect(pr.sourceBranch, 'feat/graph');
      expect(pr.targetBranch, 'main');
      expect(pr.headSha, 'abc123');
      expect(pr.author.login, 'ada');
      expect(pr.author.shown, 'Ada L.');
      expect(pr.updatedAt, DateTime.utc(2026, 9, 20, 10, 11, 12));
    });

    test('a draft reads as draft, not as open', () {
      final prs = parseMergeRequests(fixture('merge_requests.json'));

      expect(prs[0].state, PullRequestState.open);
      expect(prs[1].state, PullRequestState.draft);
    });

    test('the legacy work_in_progress spelling still reads as draft', () {
      // Older GitLab releases send only this field; a draft is still shown
      // as not-ready for whoever asked for something unfinished.
      final prs = parseMergeRequests([
        {
          'iid': 1,
          'title': 't',
          'state': 'opened',
          'work_in_progress': true,
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'aa',
        },
      ]);

      expect(prs.single.state, PullRequestState.draft);
    });

    test('merged and closed states are kept apart', () {
      final prs = parseMergeRequests([
        {
          'iid': 1,
          'title': 't',
          'state': 'merged',
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'aa',
        },
        {
          'iid': 2,
          'title': 't',
          'state': 'closed',
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'bb',
        },
        {
          'iid': 3,
          'title': 't',
          'state': 'locked',
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'cc',
        },
      ]);

      expect(prs[0].state, PullRequestState.merged);
      expect(prs[1].state, PullRequestState.closed);
      // Locked means discussion is frozen, not that the request left open;
      // it belongs with open rather than closed.
      expect(prs[2].state, PullRequestState.open);
    });

    test('skips an entry missing its head sha', () {
      final prs = parseMergeRequests(fixture('merge_requests.json'));

      expect(prs.map((p) => p.number), [42, 43]);
    });

    test('skips an entry missing fields it cannot do without', () {
      final partial = [
        {'title': 'no iid'},
        {
          'iid': 5,
          'title': 'fine',
          'state': 'opened',
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'aa',
        },
      ];

      final prs = parseMergeRequests(partial);
      expect(prs, hasLength(1));
      expect(prs.single.number, 5);
    });

    test('returns empty rather than throwing when shape is wrong', () {
      expect(parseMergeRequests(null), isEmpty);
      expect(parseMergeRequests(const {'unexpected': 'object'}), isEmpty);
      expect(parseMergeRequests(const ['not an object']), isEmpty);
      expect(parseMergeRequests(const [null]), isEmpty);
    });

    test('defaults absent optional fields instead of failing', () {
      final sparse = [
        {
          'iid': 6,
          'title': 'sparse',
          'state': 'opened',
          'source_branch': 's',
          'target_branch': 'm',
          'sha': 'aa',
        },
      ];
      final pr = parseMergeRequests(sparse).single;
      expect(pr.updatedAt, isNull);
      expect(pr.author.avatarUrl, isEmpty);
      expect(pr.author.login, 'unknown');
    });

    test('the returned list cannot be edited by its caller', () {
      final prs = parseMergeRequests(fixture('merge_requests.json'));
      expect(() => prs.add(prs.first), throwsUnsupportedError);
    });
  });

  group('parseCommitStatuses', () {
    test('counts a job only once, at its newest attempt', () {
      // The endpoint returns every attempt for a retried job, so it can
      // appear more than once under one name. Counting the old failure
      // would let a red attempt outvote the green retry that replaced it,
      // since ChecksSummary ranks failure highest.
      final summary = parseCommitStatuses(fixture('statuses.json'));

      expect(summary.runs.where((r) => r.name == 'build').length, 1);
      expect(
        summary.runs.firstWhere((r) => r.name == 'build').state,
        CheckState.success,
      );
    });

    test('a failure GitLab allows does not paint the row red', () {
      final summary = parseCommitStatuses(fixture('statuses.json'));

      expect(
        summary.runs.firstWhere((r) => r.name == 'lint').state,
        CheckState.unknown,
      );
      expect(summary.overall, isNot(ChecksOverall.failure));
      // Nor does it claim success: unknown leaves the summary mixed.
      expect(summary.overall, isNot(ChecksOverall.success));
    });

    test('a manual job nobody triggered is not a result at all', () {
      // GitLab does not count an untriggered manual job against the
      // pipeline's own verdict, so a summary built from these rows must not
      // carry one either — recording it as skipped drags an otherwise green
      // pipeline off success.
      final summary = parseCommitStatuses(fixture('statuses.json'));

      expect(summary.runs.map((r) => r.name), isNot(contains('deploy')));
    });

    test('a green pipeline with a manual job left over reads as success', () {
      // The common shape of a manually-gated .gitlab-ci.yml: everything ran
      // and passed, and one deploy job waits for a person to press it.
      final summary = parseCommitStatuses([
        {'id': 1, 'name': 'build', 'status': 'success'},
        {'id': 2, 'name': 'test', 'status': 'success'},
        {'id': 3, 'name': 'deploy', 'status': 'manual'},
      ]);

      expect(summary.overall, ChecksOverall.success);
      expect(summary.runs.map((r) => r.name), ['build', 'test']);
    });

    test('a pipeline that is nothing but manual jobs reports no CI', () {
      expect(
        parseCommitStatuses([
          {'id': 1, 'name': 'deploy', 'status': 'manual'},
        ]).overall,
        ChecksOverall.none,
      );
    });

    test('a skipped job still counts, and still leaves the summary mixed', () {
      // Skipped is a real outcome GitLab reached: the job was reached and
      // deliberately not run. Only manual is dropped.
      final summary = parseCommitStatuses([
        {'id': 1, 'name': 'build', 'status': 'success'},
        {'id': 2, 'name': 'test', 'status': 'skipped'},
      ]);

      expect(summary.runs.map((r) => r.name), ['build', 'test']);
      expect(summary.overall, ChecksOverall.mixed);
    });

    test('a manual retry of a failed job drops the job, not just the '
        'newest attempt', () {
      // Newest attempt wins, as everywhere else here. A job whose latest
      // entry is manual has no current result, so the older failure it
      // replaced must not stand in for one.
      final summary = parseCommitStatuses([
        {'id': 1, 'name': 'deploy', 'status': 'failed'},
        {'id': 2, 'name': 'deploy', 'status': 'manual'},
      ]);

      expect(summary.runs, isEmpty);
      expect(summary.overall, ChecksOverall.none);
    });

    test('carries the description through as the details hint', () {
      final summary = parseCommitStatuses(fixture('statuses.json'));

      expect(
        summary.runs.firstWhere((r) => r.name == 'lint').detailsHint,
        'non-blocking',
      );
    });

    test('maps every state GitLab documents', () {
      CheckState stateOf(String status) => parseCommitStatuses([
        {'id': 1, 'name': 'j', 'status': status},
      ]).runs.single.state;

      expect(stateOf('created'), CheckState.queued);
      expect(stateOf('pending'), CheckState.queued);
      expect(stateOf('running'), CheckState.running);
      expect(stateOf('success'), CheckState.success);
      expect(stateOf('failed'), CheckState.failure);
      expect(stateOf('canceled'), CheckState.cancelled);
      expect(stateOf('skipped'), CheckState.skipped);
      // 'manual' is deliberately absent here: it produces no run at all,
      // which the tests above pin down.
      // A forge adding a status this version does not recognise must
      // never be reported as passing.
      expect(stateOf('martian'), CheckState.unknown);
    });

    test('an empty or missing list reads as no CI rather than throwing', () {
      expect(
        parseCommitStatuses(const <Object?>[]).overall,
        ChecksOverall.none,
      );
      expect(parseCommitStatuses(null).overall, ChecksOverall.none);
      expect(parseCommitStatuses('nonsense').overall, ChecksOverall.none);
      expect(parseCommitStatuses(const [null]).overall, ChecksOverall.none);
    });

    test('skips an entry carrying no name to show', () {
      final summary = parseCommitStatuses([
        {'id': 1, 'status': 'success'},
        {'id': 2, 'name': 'named', 'status': 'success'},
      ]);

      expect(summary.runs.map((r) => r.name), ['named']);
    });

    test('the returned run list cannot be edited by its caller', () {
      final summary = parseCommitStatuses(fixture('statuses.json'));
      expect(
        () => summary.runs.add(summary.runs.first),
        throwsUnsupportedError,
      );
    });
  });

  group('parseGitlabIssues', () {
    test('reads the fields the UI needs', () {
      final issue = parseGitlabIssues(fixture('issues.json')).single;

      expect(issue.number, 7);
      expect(issue.title, 'Crash on open');
      expect(issue.state, IssueState.open);
      expect(issue.labels, ['bug', 'needs triage']);
      expect(issue.author.login, 'reporter');
      expect(issue.updatedAt, DateTime.utc(2026, 9, 18, 8));
    });

    test('an entry with no title is skipped', () {
      expect(parseGitlabIssues(fixture('issues.json')).length, 1);
    });

    test('a closed issue reads as closed', () {
      final issues = parseGitlabIssues([
        {'iid': 1, 'title': 't', 'state': 'closed'},
      ]);

      expect(issues.single.state, IssueState.closed);
    });

    test('an unrecognised state reads open, not closed', () {
      final issues = parseGitlabIssues([
        {'iid': 9, 'title': 'odd', 'state': 'martian'},
      ]);

      expect(issues.single.state, IssueState.open);
    });

    test('returns empty rather than throwing when shape is wrong', () {
      expect(parseGitlabIssues(null), isEmpty);
      expect(parseGitlabIssues(const {'unexpected': 'object'}), isEmpty);
      expect(parseGitlabIssues(const ['not an object']), isEmpty);
      expect(parseGitlabIssues(const [null]), isEmpty);
    });

    test('skips an entry with no iid or title', () {
      final partial = [
        {'title': 'no iid'},
        {'iid': 5},
        {'iid': 6, 'title': 'fine', 'state': 'opened'},
      ];
      expect(parseGitlabIssues(partial).map((i) => i.number), [6]);
    });

    test('defaults absent optional fields instead of failing', () {
      final sparse = [
        {'iid': 6, 'title': 'fine', 'state': 'opened'},
      ];
      final issue = parseGitlabIssues(sparse).single;
      expect(issue.labels, isEmpty);
      expect(issue.updatedAt, isNull);
      expect(issue.author.login, 'unknown');
    });

    test('the returned list cannot be edited by its caller', () {
      final issues = parseGitlabIssues(fixture('issues.json'));
      expect(() => issues.add(issues.first), throwsUnsupportedError);
    });
  });
}
