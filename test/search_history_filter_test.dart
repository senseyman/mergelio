// The author and date filters. Both are answered by git across the whole
// history, so a loaded commit matches only when git reported its sha.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';

Commit _c(String sha, {String author = 'Ada', DateTime? date}) => Commit(
  sha: sha,
  message: 'msg $sha',
  author: author,
  authorEmail: '${author.toLowerCase()}@e',
  date: date ?? DateTime(2026, 7, 1),
);

void main() {
  group('CommitQuery', () {
    test('an author or a date makes a history filter', () {
      expect(const CommitQuery().hasHistoryFilter, isFalse);
      expect(const CommitQuery(author: 'ada').hasHistoryFilter, isTrue);
      expect(CommitQuery(since: DateTime(2026)).hasHistoryFilter, isTrue);
      expect(CommitQuery(until: DateTime(2026)).hasHistoryFilter, isTrue);
    });

    test('a blank author is no filter', () {
      expect(const CommitQuery(author: '  ').hasHistoryFilter, isFalse);
      expect(const CommitQuery(author: '  ').isEmpty, isTrue);
    });

    test('a date alone is a search', () {
      expect(CommitQuery(since: DateTime(2026)).isEmpty, isFalse);
      expect(CommitQuery(until: DateTime(2026)).isEmpty, isFalse);
    });

    test('withDates sets and clears both ends', () {
      final q = const CommitQuery(text: 'x')
          .withDates(DateTime(2026, 1, 1), DateTime(2026, 2, 1));
      expect(q.since, DateTime(2026, 1, 1));
      expect(q.until, DateTime(2026, 2, 1));
      expect(q.text, 'x');

      final cleared = q.withDates(null, null);
      expect(cleared.since, isNull);
      expect(cleared.until, isNull);
    });

    test('copyWith keeps the dates', () {
      final q = CommitQuery(
        since: DateTime(2026, 1, 1),
        until: DateTime(2026, 2, 1),
      ).copyWith(text: 'x');
      expect(q.since, DateTime(2026, 1, 1));
      expect(q.until, DateTime(2026, 2, 1));
    });
  });

  group('authoredWithin', () {
    final since = DateTime(2026, 3, 10);
    final until = DateTime(2026, 3, 12);

    test('both ends are whole days, inclusive', () {
      expect(authoredWithin(DateTime(2026, 3, 10), since, until), isTrue);
      expect(
        authoredWithin(DateTime(2026, 3, 12, 23, 59, 59), since, until),
        isTrue,
      );
    });

    test('outside the range is out', () {
      expect(
        authoredWithin(DateTime(2026, 3, 9, 23, 59, 59), since, until),
        isFalse,
      );
      expect(authoredWithin(DateTime(2026, 3, 13), since, until), isFalse);
    });

    test('an open end does not limit', () {
      expect(authoredWithin(DateTime(1999), null, until), isTrue);
      expect(authoredWithin(DateTime(2099), since, null), isTrue);
      expect(authoredWithin(DateTime(2099), null, null), isTrue);
    });

    test('a time of day on the bounds is ignored', () {
      expect(
        authoredWithin(
          DateTime(2026, 3, 10, 1),
          DateTime(2026, 3, 10, 18),
          DateTime(2026, 3, 10, 2),
        ),
        isTrue,
      );
    });
  });

  group('historyFilterArgs', () {
    test('the author is matched literally, ignoring case and mailmap', () {
      final args = historyFilterArgs('Bob (dev)', null);
      expect(args.first, 'log');
      expect(args, containsAll(['--all', '--no-use-mailmap', '-i', '-F']));
      expect(args, contains('--author=Bob (dev)'));
    });

    test('an author that looks like an option stays the pattern', () {
      expect(historyFilterArgs('-x', null), contains('--author=-x'));
    });

    test('no author, no author flags', () {
      final args = historyFilterArgs('', DateTime(2026));
      expect(args.where((a) => a.startsWith('--author')), isEmpty);
      expect(args, isNot(contains('-F')));
    });

    test('the start date prunes the walk from local midnight', () {
      final since = DateTime(2026, 3, 10, 15);
      expect(
        historyFilterArgs('', since),
        contains('--since=2026-03-10 00:00:00'),
      );
    });

    // git reads `@<n>` as a timestamp only for long numbers, so an early
    // date written that way pruned commits it should have kept.
    test('an early start date is written as a date, not a timestamp', () {
      expect(
        historyFilterArgs('', DateTime(1971, 6, 1)),
        contains('--since=1971-06-01 00:00:00'),
      );
    });

    test('hiding merges leaves them out of the walk', () {
      expect(
        historyFilterArgs('a', null, noMerges: true),
        contains('--no-merges'),
      );
      expect(historyFilterArgs('a', null), isNot(contains('--no-merges')));
    });

    test('no end date is passed: git would compare the committer date', () {
      expect(
        historyFilterArgs(
          'a',
          DateTime(2026),
        ).where((a) => a.startsWith('--until') || a.startsWith('--before')),
        isEmpty,
      );
    });

    test('sha and author time are printed for each commit', () {
      expect(historyFilterArgs('a', null), contains('--format=%H%x00%at'));
    });
  });

  group('matchesCommit with a history filter', () {
    test('only the commits git reported match', () {
      final q = const CommitQuery(author: 'ada');
      expect(matchesCommit(_c('aaa'), q, historyShas: const {'aaa'}), isTrue);
      expect(matchesCommit(_c('bbb'), q, historyShas: const {'aaa'}), isFalse);
    });

    test('the loaded author name is not consulted: git is the answer', () {
      // The email matched, which the loaded name could not have told.
      final q = const CommitQuery(author: 'corp.io');
      expect(
        matchesCommit(_c('aaa', author: 'Ada'), q, historyShas: const {'aaa'}),
        isTrue,
      );
    });

    test('nothing matches before the read lands', () {
      expect(matchesCommit(_c('aaa'), const CommitQuery(author: 'a')), isFalse);
      expect(
        matchesCommit(_c('aaa'), CommitQuery(since: DateTime(2026))),
        isFalse,
      );
    });

    test('the other filters still apply on top', () {
      final q = const CommitQuery(author: 'ada', text: 'zzz');
      expect(matchesCommit(_c('aaa'), q, historyShas: const {'aaa'}), isFalse);
    });

    test('without a history filter the set is ignored', () {
      expect(
        matchesCommit(
          _c('aaa'),
          const CommitQuery(text: 'msg'),
          historyShas: const {},
        ),
        isTrue,
      );
    });
  });

  group('olderMatchCount', () {
    final loaded = [_c('aaa'), _c('bbb')];

    test('counts history matches that are not loaded', () {
      expect(olderMatchCount(loaded, const {'aaa', 'xxx', 'yyy'}), 2);
    });

    test('a path or content filter has to agree', () {
      expect(
        olderMatchCount(
          loaded,
          const {'aaa', 'xxx', 'yyy'},
          pathShas: const {'xxx', 'yyy'},
          contentShas: const {'yyy'},
        ),
        1,
      );
    });

    test('nothing older when everything is loaded', () {
      expect(olderMatchCount(loaded, const {'aaa', 'bbb'}), 0);
    });
  });
}
