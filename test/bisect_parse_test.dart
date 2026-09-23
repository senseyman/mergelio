import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';

void main() {
  group('parseBisectRefs', () {
    test('reads bad, good and skip marks', () {
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/bad\n'
        'bbb2222 refs/bisect/good-bbb2222\n'
        'ccc3333 refs/bisect/skip-ccc3333\n',
      );
      expect(marks, hasLength(3));
      expect(marks[0].sha, 'aaa1111');
      expect(marks[0].kind, BisectKind.bad);
      expect(marks[1].kind, BisectKind.good);
      expect(marks[2].kind, BisectKind.skip);
    });

    test('takes the sha from the ref target, not the name suffix', () {
      // git writes the same sha in both places, but the target is what the
      // ref actually points at, so that is the one to trust.
      final marks = parseBisectRefs('deadbee refs/bisect/good-ffffffff\n');
      expect(marks.single.sha, 'deadbee');
    });

    test('ignores blank lines and unrecognised refs', () {
      final marks = parseBisectRefs(
        '\n'
        'aaa1111 refs/bisect/bad\n'
        'ddd4444 refs/bisect/something-else\n',
      );
      expect(marks, hasLength(1));
      expect(marks.single.kind, BisectKind.bad);
    });

    test('empty output yields no marks', () {
      expect(parseBisectRefs(''), isEmpty);
    });

    test('reads refs named after the repository own terms', () {
      // `git bisect start --term-old=works --term-new=broken` makes git name
      // the refs after those words, so nothing here may assume good/bad.
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/broken\n'
        'bbb2222 refs/bisect/works-bbb2222\n'
        'ccc3333 refs/bisect/skip-ccc3333\n',
        const BisectTerms(bad: 'broken', good: 'works'),
      );
      expect(marks, hasLength(3));
      expect(marks[0].kind, BisectKind.bad);
      expect(marks[0].sha, 'aaa1111');
      expect(marks[1].kind, BisectKind.good);
      expect(marks[1].sha, 'bbb2222');
      expect(marks[2].kind, BisectKind.skip);
    });

    test('reads the old/new term pair', () {
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/new\n'
        'bbb2222 refs/bisect/old-bbb2222\n',
        const BisectTerms(bad: 'new', good: 'old'),
      );
      expect(marks.map((m) => m.kind), [BisectKind.bad, BisectKind.good]);
    });

    test('a term containing a hyphen is not cut short at the hyphen', () {
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/still-broken\n'
        'bbb2222 refs/bisect/known-good-bbb2222\n',
        const BisectTerms(bad: 'still-broken', good: 'known-good'),
      );
      expect(marks.map((m) => m.kind), [BisectKind.bad, BisectKind.good]);
    });

    test('a term does not match a ref that merely starts with it', () {
      // A ref named "older-<sha>" must not be bucketed under the shorter
      // term "old" just because the name starts with it — only a bare match
      // or a match cut at the term's own trailing hyphen counts.
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/old-aaa1111\n'
        'bbb2222 refs/bisect/older-bbb2222\n',
        const BisectTerms(bad: 'new', good: 'old'),
      );
      expect(marks, hasLength(1));
      expect(marks.single.sha, 'aaa1111');
      expect(marks.single.kind, BisectKind.good);
    });

    test('skip keeps its own name when the terms are renamed', () {
      // Skip is a subcommand rather than a term, so git never renames it —
      // and renamed terms must not swallow its refs either.
      final marks = parseBisectRefs(
        'ccc3333 refs/bisect/skip-ccc3333\n',
        const BisectTerms(bad: 'broken', good: 'works'),
      );
      expect(marks.single.kind, BisectKind.skip);
    });

    test('default good/bad refs are ignored once the terms are renamed', () {
      // Under renamed terms git writes no good/bad refs, so anything left
      // under those names belongs to no live verdict and is not a mark.
      final marks = parseBisectRefs(
        'aaa1111 refs/bisect/bad\n'
        'bbb2222 refs/bisect/good-bbb2222\n',
        const BisectTerms(bad: 'broken', good: 'works'),
      );
      expect(marks, isEmpty);
    });
  });

  group('parseBisectTerms', () {
    test('reads the bad term from line 1 and the good term from line 2', () {
      final t = parseBisectTerms('broken\nworking\n');
      expect(t.bad, 'broken');
      expect(t.good, 'working');
    });

    test('null contents fall back to good and bad', () {
      final t = parseBisectTerms(null);
      expect(t.bad, 'bad');
      expect(t.good, 'good');
    });

    test('a single-line file falls back rather than guessing', () {
      final t = parseBisectTerms('broken\n');
      expect(t.bad, 'bad');
      expect(t.good, 'good');
    });
  });
}
