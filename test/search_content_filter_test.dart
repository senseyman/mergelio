// Filtering the graph down to the commits whose diff touched a string — the
// pickaxe. Which commits those are cannot be told from a commit alone, so the
// matcher is handed the shas git reported.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';

Commit _c(String sha, {String message = 'msg', String author = 'Tester'}) =>
    Commit(
      sha: sha,
      message: message,
      author: author,
      authorEmail: 't@e',
      date: DateTime(2026, 7, 1),
      parents: const [],
    );

void main() {
  final commits = [_c('aaa'), _c('bbb'), _c('ccc')];

  test('a content filter alone is a filter, not an empty query', () {
    expect(const CommitQuery(content: 'parseUrl').isEmpty, isFalse);
    expect(const CommitQuery().isEmpty, isTrue);
  });

  test('only the commits whose diff touched the string match', () {
    const q = CommitQuery(content: 'parseUrl');
    const touched = {'aaa', 'ccc'};

    expect(
      [
        for (final c in commits)
          if (matchesCommit(c, q, contentShas: touched)) c.sha,
      ],
      ['aaa', 'ccc'],
    );
  });

  test('nothing matches until the pickaxe result has arrived', () {
    const q = CommitQuery(content: 'parseUrl');

    expect(matchesCommit(commits.first, q), isFalse);
  });

  test('the other filters still apply on top of the content', () {
    const touched = {'aaa', 'bbb'};
    final byAuthor = [_c('aaa', author: 'Ada'), _c('bbb', author: 'Grace')];

    expect(
      [
        for (final c in byAuthor)
          if (matchesCommit(
            c,
            const CommitQuery(content: 'parseUrl', author: 'Ada'),
            contentShas: touched,
          ))
            c.sha,
      ],
      ['aaa'],
    );
  });

  test('a path filter and a content filter both have to hold', () {
    const q = CommitQuery(path: 'lib/main.dart', content: 'parseUrl');

    expect(
      [
        for (final c in commits)
          if (matchesCommit(
            c,
            q,
            pathShas: const {'aaa', 'bbb'},
            contentShas: const {'bbb', 'ccc'},
          ))
            c.sha,
      ],
      ['bbb'],
    );
  });

  test('a search with no content is unaffected by a content set', () {
    expect(
      searchCommits(commits, const CommitQuery(text: 'msg')).length,
      commits.length,
    );
  });

  test('the mode defaults to counting occurrences of a literal string', () {
    expect(const CommitQuery().contentMode, ContentSearchMode.occurrences);
  });

  test('copyWith carries the content and its mode', () {
    const q = CommitQuery(
      content: 'parseUrl',
      contentMode: ContentSearchMode.diffText,
    );

    expect(q.copyWith(text: 'x').content, 'parseUrl');
    expect(q.copyWith(text: 'x').contentMode, ContentSearchMode.diffText);
    expect(q.copyWith(content: '').content, isEmpty);
  });

  test('the isolate path produces the same match set', () async {
    const q = CommitQuery(content: 'parseUrl');

    expect(await computeMatchShas(commits, q, contentShas: const {'bbb'}), {
      'bbb',
    });
  });
}
