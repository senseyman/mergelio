import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/reflog.dart';

const _fs = '\x1f';
const _rs = '\x00';

/// Builds one `git log -g -z` record in the field order the reader asks for:
/// sha, selector, subject, author, email, date.
String _rec({
  String sha = 'aaaaaaaabbbbbbbbccccccccdddddddd11111111',
  String selector = 'HEAD@{0}',
  String subject = 'commit: add thing',
  String author = 'Neo',
  String email = 'neo@example.com',
  String date = '2026-09-15T12:34:56+01:00',
}) => [sha, selector, subject, author, email, date].join(_fs);

void main() {
  test('parses every field of one entry', () {
    final entries = parseReflog(_rec());

    expect(entries, hasLength(1));
    final e = entries.single;
    expect(e.sha, 'aaaaaaaabbbbbbbbccccccccdddddddd11111111');
    expect(e.selector, 'HEAD@{0}');
    expect(e.author, 'Neo');
    expect(e.email, 'neo@example.com');
    expect(e.date, DateTime.parse('2026-09-15T12:34:56+01:00'));
    expect(e.dateOffset, const Duration(hours: 1));
  });

  test(
    'splits the reflog subject into action and detail at the first colon',
    () {
      final e = parseReflog(_rec(subject: 'reset: moving to HEAD~1')).single;

      expect(e.action, 'reset');
      expect(e.detail, 'moving to HEAD~1');
    },
  );

  test('keeps a parenthesised action whole', () {
    final e = parseReflog(
      _rec(subject: 'rebase (finish): returning to refs/heads/main'),
    ).single;

    expect(e.action, 'rebase (finish)');
    expect(e.detail, 'returning to refs/heads/main');
  });

  test('a later colon does not split the action', () {
    // `checkout: moving from a to b` — only the first `: ` separates the verb,
    // and the detail keeps any colon of its own.
    final e = parseReflog(
      _rec(subject: 'merge topic: Merge made by the ort strategy: ok'),
    ).single;

    expect(e.action, 'merge topic');
    expect(e.detail, 'Merge made by the ort strategy: ok');
  });

  test('a subject with no colon is all action and no detail', () {
    final e = parseReflog(_rec(subject: 'rebase')).single;

    expect(e.action, 'rebase');
    expect(e.detail, '');
  });

  test('parses several records in emitted order', () {
    final entries = parseReflog(
      [
        _rec(selector: 'HEAD@{0}', sha: 'f' * 40),
        _rec(selector: 'HEAD@{1}', sha: 'e' * 40),
      ].join(_rs),
    );

    expect(entries.map((e) => e.selector), ['HEAD@{0}', 'HEAD@{1}']);
    expect(entries.map((e) => e.sha), ['f' * 40, 'e' * 40]);
  });

  test('empty output yields no entries', () {
    expect(parseReflog(''), isEmpty);
  });

  test('a trailing record separator yields no phantom entry', () {
    expect(parseReflog('${_rec()}$_rs'), hasLength(1));
  });

  test('a record short of its fields is skipped', () {
    // An interrupted git or a torn read can leave a partial trailing record;
    // it must not surface as an entry with empty fields.
    final entries = parseReflog(
      [
        _rec(),
        ['deadbeef', 'HEAD@{1}'].join(_fs),
      ].join(_rs),
    );

    expect(entries, hasLength(1));
    expect(entries.single.selector, 'HEAD@{0}');
  });

  test('a record with an unparseable date is skipped', () {
    final entries = parseReflog(
      [_rec(), _rec(selector: 'HEAD@{1}', date: 'not-a-date')].join(_rs),
    );

    expect(entries.map((e) => e.selector), ['HEAD@{0}']);
  });

  test('shortSha abbreviates to seven characters', () {
    expect(parseReflog(_rec(sha: 'a' * 40)).single.shortSha, 'aaaaaaa');
  });
}
