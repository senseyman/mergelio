import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';

Commit _c(
  String sha,
  String msg,
  String author, {
  List<String> parents = const [],
}) => Commit(
  sha: sha,
  message: msg,
  author: author,
  authorEmail: '$author@e',
  date: DateTime(2026),
  parents: parents,
);

void main() {
  group('searchCommits', () {
    final commits = [
      _c('aaaaaaa', 'fix login bug', 'Maria'),
      _c('bbbbbbb', 'add search', 'Ivan'),
      _c('ccccccc', 'Merge feature', 'Maria', parents: ['x', 'y']),
    ];

    test('matches message, author or sha prefix', () {
      expect(
        searchCommits(commits, const CommitQuery(text: 'login')).single.sha,
        'aaaaaaa',
      );
      expect(
        searchCommits(commits, const CommitQuery(text: 'ivan')).single.sha,
        'bbbbbb'.padLeft(7, 'b'),
      );
      expect(
        searchCommits(commits, const CommitQuery(text: 'ccc')).single.message,
        'Merge feature',
      );
    });

    test('author filter narrows results', () {
      final r = searchCommits(
        commits,
        const CommitQuery(text: '', author: 'Maria', hideMerges: false),
      );
      expect(r.map((c) => c.author).toSet(), {'Maria'});
      expect(r, hasLength(2));
    });

    test('hideTags drops commits carrying a tag ref', () {
      final tagged = Commit(
        sha: 'ddddddd',
        message: 'release',
        author: 'Maria',
        authorEmail: 'm@e',
        date: DateTime(2026),
        refs: const [GitRef(kind: RefKind.tag, name: 'v1.0')],
      );
      final r = searchCommits([
        ...commits,
        tagged,
      ], const CommitQuery(author: 'Maria', hideTags: true));
      expect(r.map((c) => c.sha), isNot(contains('ddddddd')));
    });

    test('hideMerges drops merge commits', () {
      final r = searchCommits(
        commits,
        const CommitQuery(author: 'Maria', hideMerges: true),
      );
      expect(r.every((c) => !c.merge), isTrue);
      expect(r, hasLength(1));
    });

    test('an empty query returns nothing', () {
      expect(searchCommits(commits, const CommitQuery()), isEmpty);
    });
  });

  group('fuzzyScore', () {
    test('non-subsequence returns null', () {
      expect(fuzzyScore('xyz', 'checkout'), isNull);
    });

    test('subsequence matches; contiguous and word-start score higher', () {
      expect(fuzzyScore('co', 'checkout'), isNotNull);
      // "che" (contiguous, word start) beats scattered "cko".
      expect(
        fuzzyScore('che', 'checkout')!,
        greaterThan(fuzzyScore('cko', 'checkout')!),
      );
    });

    test('empty pattern scores zero', () {
      expect(fuzzyScore('', 'anything'), 0);
    });
  });

  group('fuzzyRank', () {
    test('ranks best matches first and drops non-matches', () {
      final ranked = fuzzyRank('co', ['Commit', 'Checkout', 'Fetch'], (s) => s);
      expect(ranked, ['Commit', 'Checkout']); // both match, Commit ranks first
    });
  });
}
