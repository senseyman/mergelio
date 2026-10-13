import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/graph_selection.dart';

void main() {
  // Graph order: newest first, as the list shows it.
  const order = ['e', 'd', 'c', 'b', 'a'];

  group('CommitPicks', () {
    test('toggle on an empty set seeds it with the selected commit', () {
      final p = CommitPicks.none.toggle('b', seed: 'd');
      expect(p.shas, {'d', 'b'});
      expect(p.anchor, 'b');
    });

    test('toggle ignores a WIP or missing seed and the clicked row itself', () {
      expect(CommitPicks.none.toggle('b', seed: wipSelection).shas, {'b'});
      expect(CommitPicks.none.toggle('b', seed: null).shas, {'b'});
      expect(CommitPicks.none.toggle('b', seed: 'b').shas, {'b'});
    });

    test('toggle removes a picked row and ignores the seed then', () {
      final p = CommitPicks.none.toggle('b', seed: 'd').toggle('d', seed: 'b');
      expect(p.shas, {'b'});
    });

    test('toggling the last row out empties the set', () {
      final p = CommitPicks.none.toggle('b').toggle('b');
      expect(p.isEmpty, isTrue);
      expect(p.anchor, isNull);
    });

    test('extend picks the run from the anchor, replacing the set', () {
      final p = CommitPicks.none
          .toggle('a')
          .toggle('e')
          .extend('c', order, seed: null);
      // Anchor is the last toggled row, 'e'.
      expect(p.shas, {'e', 'd', 'c'});
      expect(p.anchor, 'e');
    });

    test('extend with no anchor runs from the selected commit', () {
      final p = CommitPicks.none.extend('b', order, seed: 'd');
      expect(p.shas, {'d', 'c', 'b'});
      expect(p.anchor, 'd');
    });

    test('extend with nothing usable picks only the clicked row', () {
      expect(CommitPicks.none.extend('b', order, seed: null).shas, {'b'});
      expect(CommitPicks.none.extend('b', order, seed: wipSelection).shas, {
        'b',
      });
      expect(CommitPicks.none.extend('zz', order, seed: 'd').shas, {'zz'});
    });

    test('oldestFirst follows graph order, not click order', () {
      final p = CommitPicks.none.toggle('a').toggle('d').toggle('b');
      expect(p.oldestFirst(order), ['a', 'b', 'd']);
    });

    test('oldestFirst drops picks no longer in the graph', () {
      final p = CommitPicks.none.toggle('gone').toggle('c');
      expect(p.oldestFirst(order), ['c']);
    });
  });

  group('firstMergeOf', () {
    Commit c(String sha, List<String> parents) => Commit(
      sha: sha,
      parents: parents,
      author: 'A',
      authorEmail: 'a@x',
      date: DateTime(2026),
      message: sha,
    );

    test('names the first merge commit', () {
      expect(
        firstMergeOf([
          c('a', ['p']),
          c('m', ['a', 'x']),
        ])?.sha,
        'm',
      );
    });

    test('is null when no commit is a merge', () {
      expect(
        firstMergeOf([
          c('a', ['p']),
          c('b', ['a']),
        ]),
        isNull,
      );
    });
  });
}
