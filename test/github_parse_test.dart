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
}
