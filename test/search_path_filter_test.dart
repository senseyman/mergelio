// Filtering the graph down to the commits that touched one path — what "Show
// history" on a navigator row turns into.
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

  test('a path filter alone is a filter, not an empty query', () {
    expect(const CommitQuery(path: 'lib/main.dart').isEmpty, isFalse);
    expect(const CommitQuery().isEmpty, isTrue);
  });

  test('only the commits that touched the path match', () {
    const q = CommitQuery(path: 'lib/main.dart');
    const touched = {'aaa', 'ccc'};

    expect(
      [
        for (final c in commits)
          if (matchesCommit(c, q, pathShas: touched)) c.sha,
      ],
      ['aaa', 'ccc'],
    );
  });

  test('nothing matches until the history for the path has arrived', () {
    const q = CommitQuery(path: 'lib/main.dart');

    expect(matchesCommit(commits.first, q), isFalse);
  });

  test('the other filters still apply on top of the path', () {
    const touched = {'aaa', 'bbb'};
    final byAuthor = [_c('aaa', author: 'Ada'), _c('bbb', author: 'Grace')];

    expect(
      [
        for (final c in byAuthor)
          if (matchesCommit(
            c,
            const CommitQuery(path: 'lib/main.dart', author: 'Ada'),
            pathShas: touched,
          ))
            c.sha,
      ],
      ['aaa'],
    );
  });

  test('a search with no path is unaffected by a path set', () {
    expect(
      searchCommits(commits, const CommitQuery(text: 'msg')).length,
      commits.length,
    );
  });

  test('the isolate path produces the same match set', () async {
    const q = CommitQuery(path: 'lib/main.dart');

    expect(await computeMatchShas(commits, q, pathShas: const {'bbb'}), {
      'bbb',
    });
  });
}
