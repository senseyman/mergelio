import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/github_parse.dart';
import 'package:mergelio/domain/forge/models.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/forge/github/$name').readAsStringSync());

void main() {
  group('parsePullRequests', () {
    test('reads the fields the UI needs', () {
      final prs = parsePullRequests(fixture('pulls.json'));

      expect(prs, hasLength(4));
      final first = prs.first;
      expect(first.number, 7);
      expect(first.title, 'Fix the thing');
      expect(first.state, PullRequestState.open);
      expect(first.author.login, 'octocat');
      expect(first.author.avatarUrl, 'https://example.test/a.png');
      expect(first.sourceBranch, 'fix/thing');
      expect(first.targetBranch, 'main');
      expect(first.headSha, 'abc123');
      expect(first.updatedAt, DateTime.utc(2026, 9, 14, 10, 11, 12));
    });

    test('collapses a draft into its own state', () {
      expect(
        parsePullRequests(fixture('pulls.json'))[1].state,
        PullRequestState.draft,
      );
    });

    test('a merged request reads as merged, not merely closed', () {
      // merged_at outranks state: both are set on a landed request, and
      // "closed" would lose the distinction the UI shows.
      expect(
        parsePullRequests(fixture('pulls.json'))[2].state,
        PullRequestState.merged,
      );
    });

    test('a closed unmerged request reads as closed', () {
      expect(
        parsePullRequests(fixture('pulls.json'))[3].state,
        PullRequestState.closed,
      );
    });

    test('survives a null author, as a deleted account produces', () {
      final ghost = parsePullRequests(fixture('pulls.json'))[3].author;
      expect(ghost.login, isNotEmpty);
    });

    test('returns empty for an empty list', () {
      expect(parsePullRequests(const <Object?>[]), isEmpty);
    });

    test('returns empty rather than throwing when the shape is wrong', () {
      // A tolerant parser is the point: an API that changes shape must degrade
      // to "no data", never to a crash in a running client.
      expect(parsePullRequests(null), isEmpty);
      expect(parsePullRequests(const {'unexpected': 'object'}), isEmpty);
      expect(parsePullRequests(const ['not an object']), isEmpty);
      expect(parsePullRequests(const [null]), isEmpty);
    });

    test('rejects an envelope object instead of reading through it', () {
      // A wrapper around the list is a shape this version does not understand,
      // and reading the values out of it would be guessing at an API nobody
      // has looked at. The values here are themselves well-formed requests, so
      // anything that reached through the wrapper would quietly produce rows
      // instead of failing visibly.
      const wrapped = {
        '1': {
          'number': 1,
          'title': 'wrapped',
          'state': 'open',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      };
      expect(parsePullRequests(wrapped), isEmpty);
    });

    test('skips an entry whose number is not a number', () {
      // A number sent as a string is a different field than the one this
      // parser was written against, so the row is dropped rather than coerced.
      final stringy = [
        {
          'number': '7',
          'title': 'stringy',
          'state': 'open',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(stringy), isEmpty);
    });

    test('an unparseable timestamp reads as no timestamp', () {
      // Substituting a fallback date here would silently sort this request
      // somewhere it does not belong. Absent is the honest answer.
      final bad = [
        {
          'number': 18,
          'title': 'bad date',
          'state': 'open',
          'updated_at': 'not-a-date',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(bad).single.updatedAt, isNull);
    });

    test('a nested field of the wrong shape does not produce a row', () {
      // An array where an object belongs is exactly the "field changed shape"
      // case this parser exists to survive.
      final nested = [
        {
          'number': 19,
          'title': 'nested',
          'state': 'open',
          'head': <Object?>[],
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(nested), isEmpty);
    });

    test('skips an entry missing the fields it cannot do without', () {
      final partial = [
        {'title': 'no number'},
        {
          'number': 11,
          'title': 'fine',
          'state': 'open',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      final prs = parsePullRequests(partial);
      expect(prs, hasLength(1));
      expect(prs.single.number, 11);
    });

    test('normalises a timestamp with an offset to utc', () {
      // GitHub sends Z, but a forge behind a proxy has been seen to send a
      // local offset. Comparing an unnormalised local time against another
      // request's UTC time sorts the list wrongly.
      final offset = [
        {
          'number': 13,
          'title': 'offset',
          'state': 'open',
          'updated_at': '2026-09-14T12:11:12+02:00',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      final at = parsePullRequests(offset).single.updatedAt;
      expect(at!.isUtc, isTrue);
      expect(at, DateTime.utc(2026, 9, 14, 10, 11, 12));
    });

    test('a timestamp with no zone still comes back in utc', () {
      // Dart reads an offset-less timestamp as machine-local. Handing that
      // back would make the same instant sort differently on two machines, so
      // only the instant is asserted here, never the wall clock.
      final naive = [
        {
          'number': 17,
          'title': 'naive',
          'state': 'open',
          'updated_at': '2026-09-14T10:11:12',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(naive).single.updatedAt!.isUtc, isTrue);
    });

    test('treats an empty required field as absent', () {
      // An empty title is not a title. Letting one through puts a blank row in
      // the list with nothing to identify it by.
      final blank = [
        {
          'number': 14,
          'title': '',
          'state': 'open',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(blank), isEmpty);
    });

    test('skips an entry missing each branch ref in turn', () {
      Object? entry({Object? head, Object? base}) => {
        'number': 15,
        'title': 'fine',
        'state': 'open',
        'head': ?head,
        'base': ?base,
      };
      expect(
        parsePullRequests([
          entry(head: {'ref': 'b'}, base: {'ref': 'main'}),
        ]),
        isEmpty,
        reason: 'a head with no sha cannot be asked about CI',
      );
      expect(
        parsePullRequests([
          entry(head: {'sha': 's'}, base: {'ref': 'main'}),
        ]),
        isEmpty,
      );
      expect(
        parsePullRequests([
          entry(head: {'ref': 'b', 'sha': 's'}),
        ]),
        isEmpty,
      );
    });

    test('merged outranks draft when a request carries both', () {
      // The order of these checks is the behaviour, not an accident: a landed
      // request must never read as still-in-progress work.
      final both = [
        {
          'number': 16,
          'title': 'landed',
          'state': 'closed',
          'draft': true,
          'merged_at': '2026-09-12T09:00:00Z',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      expect(parsePullRequests(both).single.state, PullRequestState.merged);
    });

    test('the returned list cannot be edited by its caller', () {
      // Callers cache this list. A mutable one lets a later screen quietly
      // rewrite what an earlier one is still showing.
      final prs = parsePullRequests(fixture('pulls.json'));
      expect(() => prs.add(prs.first), throwsUnsupportedError);
    });

    test('defaults absent optional fields instead of failing', () {
      final sparse = [
        {
          'number': 12,
          'title': 'sparse',
          'state': 'open',
          'head': {'ref': 'b', 'sha': 's'},
          'base': {'ref': 'main'},
        },
      ];
      final pr = parsePullRequests(sparse).single;
      expect(pr.updatedAt, isNull);
      expect(pr.author.avatarUrl, isEmpty);
    });
  });

  group('parseChecks', () {
    test('merges both APIs into one run list', () {
      final summary = parseChecks(
        combinedStatus: fixture('status_combined.json'),
        checkRuns: fixture('check_runs.json'),
      );
      expect(summary.runs, hasLength(7));
      // Order is pinned, not merely membership: the list is shown to a person
      // in the order it arrives, and legacy statuses leading is the arbitrary
      // choice this code made. Changing it should be a decision, not a drift.
      expect(summary.runs.map((r) => r.name).toList(), [
        'ci/legacy-build',
        'ci/legacy-lint',
        'build',
        'test',
        'lint',
        'flaky',
        'future',
      ]);
    });

    test('an unrecognised run status becomes unknown, never success', () {
      // The conclusion is only consulted once a run reports completed, so a
      // status this version has never seen must stop at the first switch. A
      // forge adding one must not be able to paint a job green by doing so.
      final summary = parseChecks(
        checkRuns: {
          'check_runs': [
            {'name': 'martian', 'status': 'martian', 'conclusion': null},
          ],
        },
      );
      expect(summary.runs.single.state, CheckState.unknown);
      expect(summary.overall, isNot(ChecksOverall.success));
    });

    test('a failure in either API fails the summary', () {
      final summary = parseChecks(
        combinedStatus: fixture('status_combined.json'),
        checkRuns: fixture('check_runs.json'),
      );
      expect(summary.overall, ChecksOverall.failure);
    });

    test('maps check-run status and conclusion onto states', () {
      final summary = parseChecks(checkRuns: fixture('check_runs.json'));
      CheckState stateOf(String name) =>
          summary.runs.firstWhere((r) => r.name == name).state;
      expect(stateOf('build'), CheckState.success);
      expect(stateOf('test'), CheckState.running);
      expect(stateOf('lint'), CheckState.queued);
      expect(stateOf('flaky'), CheckState.cancelled);
    });

    test('an unrecognised conclusion becomes unknown, never success', () {
      // A forge adding a conclusion must never be reported green.
      final summary = parseChecks(checkRuns: fixture('check_runs.json'));
      final future = summary.runs.firstWhere((r) => r.name == 'future');
      expect(future.state, CheckState.unknown);
      expect(summary.overall, isNot(ChecksOverall.success));
    });

    test('a completed run with no conclusion is unknown, not success', () {
      // GitHub has been seen to report completed before the conclusion is
      // written. Reading the missing field as success would show green CI for
      // a job whose outcome nobody knows yet.
      final summary = parseChecks(
        checkRuns: {
          'check_runs': [
            {'name': 'racy', 'status': 'completed', 'conclusion': null},
          ],
        },
      );
      expect(summary.runs.single.state, CheckState.unknown);
      expect(summary.overall, isNot(ChecksOverall.success));
    });

    test('maps legacy commit-status states', () {
      final summary = parseChecks(
        combinedStatus: {
          'statuses': [
            {'context': 'a', 'state': 'success'},
            {'context': 'b', 'state': 'pending'},
            {'context': 'c', 'state': 'error'},
            {'context': 'd', 'state': 'failure'},
            {'context': 'e', 'state': 'martian'},
          ],
        },
      );
      CheckState stateOf(String name) =>
          summary.runs.firstWhere((r) => r.name == name).state;
      expect(stateOf('a'), CheckState.success);
      expect(stateOf('b'), CheckState.running);
      expect(stateOf('c'), CheckState.failure);
      expect(stateOf('d'), CheckState.failure);
      expect(stateOf('e'), CheckState.unknown);
    });

    test('carries whatever short explanation the API offered', () {
      final summary = parseChecks(checkRuns: fixture('check_runs.json'));
      final build = summary.runs.firstWhere((r) => r.name == 'build');
      expect(build.detailsHint, 'Built in 42s');
    });

    test('a repository with no CI at all reads as none', () {
      expect(parseChecks().overall, ChecksOverall.none);
      expect(parseChecks().runs, isEmpty);
    });

    test('a malformed payload reads as no CI rather than throwing', () {
      expect(
        parseChecks(combinedStatus: 'nonsense').overall,
        ChecksOverall.none,
      );
      expect(parseChecks(checkRuns: [1, 2, 3]).overall, ChecksOverall.none);
      expect(
        parseChecks(combinedStatus: 'nonsense', checkRuns: [1, 2, 3]).overall,
        ChecksOverall.none,
      );
    });

    test('skips an entry carrying no name to show', () {
      final summary = parseChecks(
        combinedStatus: {
          'statuses': [
            {'state': 'success'},
            {'context': 'named', 'state': 'success'},
          ],
        },
        checkRuns: {
          'check_runs': [
            {'status': 'completed', 'conclusion': 'success'},
          ],
        },
      );
      expect(summary.runs.map((r) => r.name), ['named']);
    });

    test('the returned run list cannot be edited by its caller', () {
      final summary = parseChecks(checkRuns: fixture('check_runs.json'));
      expect(
        () => summary.runs.add(summary.runs.first),
        throwsUnsupportedError,
      );
    });
  });

  group('parseIssues', () {
    test('omits pull requests, which this endpoint also returns', () {
      // Every PR is an issue in GitHub's model and arrives carrying a
      // pull_request key. Without this filter the issue list repeats the PR
      // list in full.
      final issues = parseIssues(fixture('issues.json'));
      expect(issues.map((i) => i.number), [12, 3]);
    });

    test('omits a pull request even when the key carries nothing', () {
      // The key's presence is what marks a pull request, not its contents.
      // Reading the value instead would let an empty one through and put the
      // request in both lists.
      final entries = [
        {'number': 1, 'title': 'pr', 'state': 'open', 'pull_request': null},
        {
          'number': 2,
          'title': 'pr too',
          'state': 'open',
          'pull_request': <String, Object?>{},
        },
        {'number': 3, 'title': 'a real issue', 'state': 'open'},
      ];
      expect(parseIssues(entries).map((i) => i.number), [3]);
    });

    test('reads the fields the UI needs', () {
      final issue = parseIssues(fixture('issues.json')).first;
      expect(issue.number, 12);
      expect(issue.title, 'Crash on open');
      expect(issue.state, IssueState.open);
      expect(issue.author.login, 'reporter');
      expect(issue.labels, ['bug', 'needs triage']);
      expect(issue.updatedAt, DateTime.utc(2026, 9, 14, 8));
    });

    test('reads a closed issue as closed', () {
      expect(parseIssues(fixture('issues.json'))[1].state, IssueState.closed);
    });

    test('an unrecognised state reads as open, not closed', () {
      // Guessing closed would hide the issue from the list people actually
      // work from, so an unknown state stays visible.
      final odd = [
        {'number': 9, 'title': 'odd', 'state': 'martian'},
      ];
      expect(parseIssues(odd).single.state, IssueState.open);
    });

    test('keeps the usable labels and drops a malformed one', () {
      expect(parseIssues(fixture('issues.json'))[1].labels, ['wontfix']);
    });

    test('drops a label with no name to show', () {
      // A nameless label would render as a blank chip next to the real ones,
      // which reads as a rendering fault rather than as data.
      final unnamed = [
        {
          'number': 4,
          'title': 'unnamed label',
          'state': 'open',
          'labels': [
            {'name': ''},
            {'name': 'real'},
          ],
        },
      ];
      expect(parseIssues(unnamed).single.labels, ['real']);
    });

    test('returns empty rather than throwing when the shape is wrong', () {
      expect(parseIssues(null), isEmpty);
      expect(parseIssues(const {'unexpected': 'object'}), isEmpty);
      expect(parseIssues(const ['not an object']), isEmpty);
      expect(parseIssues(const [null]), isEmpty);
    });

    test('skips an entry with no number or title', () {
      final partial = [
        {'title': 'no number'},
        {'number': 5},
        {'number': 6, 'title': 'fine', 'state': 'open'},
      ];
      expect(parseIssues(partial).map((i) => i.number), [6]);
    });

    test('treats an empty title as absent', () {
      final blank = [
        {'number': 8, 'title': '', 'state': 'open'},
      ];
      expect(parseIssues(blank), isEmpty);
    });

    test('defaults absent optional fields', () {
      final sparse = [
        {'number': 6, 'title': 'fine', 'state': 'open'},
      ];
      final issue = parseIssues(sparse).single;
      expect(issue.labels, isEmpty);
      expect(issue.updatedAt, isNull);
      expect(issue.author.login, isNotEmpty);
    });

    test('the returned list cannot be edited by its caller', () {
      final issues = parseIssues(fixture('issues.json'));
      expect(() => issues.add(issues.first), throwsUnsupportedError);
    });
  });

  group('parseRateLimit', () {
    test('reads the core resource', () {
      final limit = parseRateLimit({
        'resources': {
          'core': {'limit': 60, 'remaining': 57, 'reset': 1789000000},
        },
      });
      expect(limit, isNotNull);
      expect(limit!.limit, 60);
      expect(limit.remaining, 57);
      expect(
        limit.resetAt,
        DateTime.fromMillisecondsSinceEpoch(1789000000 * 1000, isUtc: true),
      );
    });

    test('a reset the forge did not send is simply absent', () {
      final limit = parseRateLimit({
        'resources': {
          'core': {'limit': 60, 'remaining': 57},
        },
      });
      expect(limit!.resetAt, isNull);
    });

    test('returns null rather than throwing on a shape it cannot read', () {
      expect(parseRateLimit(null), isNull);
      expect(parseRateLimit('nonsense'), isNull);
      expect(parseRateLimit(const {'resources': 'nope'}), isNull);
      expect(
        parseRateLimit(const {
          'resources': {'core': 'nope'},
        }),
        isNull,
      );
      expect(
        parseRateLimit(const {
          'resources': {'core': {}},
        }),
        isNull,
      );
    });
  });
}
