import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';

Commit _c(String sha, List<String> parents) => Commit(
  sha: sha,
  message: sha,
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  parents: parents,
);

void main() {
  group('assignLanes', () {
    // A merge of a feature branch back into main:
    //   merge -> [m1 (main), f2 (feature tip)]
    //   f2 -> [f1]     f1 -> [m1] (branched from main)
    //   m1 -> [m0]     m0 -> [] (root)
    // Newest-first topological order.
    final laned = assignLanes([
      _c('merge', ['m1', 'f2']),
      _c('f2', ['f1']),
      _c('f1', ['m1']),
      _c('m1', ['m0']),
      _c('m0', []),
    ]);
    Commit at(String sha) => laned.firstWhere((c) => c.sha == sha);

    test('merge commit sits on the main lane and records mergeFrom', () {
      final m = at('merge');
      expect(m.merge, isTrue);
      expect(m.lane, 0);
      expect(m.ci, 0);
      expect(m.mergeFrom, isNotNull);
      expect(m.mergeFrom, isNot(0));
    });

    test('feature tip takes a second lane with its own colour', () {
      final f = at('f2');
      expect(f.lane, 1);
      expect(f.ci, 1);
      expect(f.through, [0, 1]);
      expect(f.branchStart, isFalse);
    });

    test('feature base is a branchStart joining the main lane', () {
      final f = at('f1');
      expect(f.lane, 1);
      expect(f.branchStart, isTrue);
      expect(f.through, [0]);
      // Its first parent m1 continues on lane 0, so the connector merges down
      // into lane 0.
      expect(f.branchInto, 0);
    });

    test('a non-branchStart commit has no branchInto', () {
      expect(at('f2').branchInto, isNull);
      expect(at('m1').branchInto, isNull);
    });

    test('only commits no child was waiting for are tips', () {
      expect(at('merge').tip, isTrue);
      expect(at('f2').tip, isFalse);
      expect(at('m1').tip, isFalse);
      expect(at('m0').tip, isFalse);
    });

    test('mainline commits stay on lane 0', () {
      expect(at('m1').lane, 0);
      expect(at('m0').lane, 0);
      expect(at('m0').branchStart, isFalse);
    });

    test('a straight chain uses a single lane', () {
      final chain = assignLanes([
        _c('c', ['b']),
        _c('b', ['a']),
        _c('a', []),
      ]);
      expect(chain.every((c) => c.lane == 0), isTrue);
      expect(chain.every((c) => c.mergeFrom == null), isTrue);
    });
  });
}
