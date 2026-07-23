import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/state/merge_session.dart';

ConflictFile _file(String path, String raw) =>
    ConflictFile(path: path, parts: parseConflicts(raw));

const _oneConflict = '<<<<<<< HEAD\nO\n=======\nT\n>>>>>>> x\n';

void main() {
  group('ConflictFile', () {
    final f = _file('a.txt', _oneConflict);

    test('counts hunks and is unresolved until every hunk is chosen', () {
      expect(f.total, 1);
      expect(f.resolved, isFalse);
      final done = f.withResolution(0, Resolution.ours);
      expect(done.resolved, isTrue);
      expect(done.content(), 'O\n');
    });

    test('custom resolution stores replacement lines', () {
      final done = f.withResolution(0, Resolution.custom, lines: ['X']);
      expect(done.content(), 'X\n');
    });
  });

  group('MergeSession', () {
    test('gates finish until all files resolved; tracks progress', () {
      var session = MergeSession(
        branch: 'feature',
        files: [_file('a.txt', _oneConflict), _file('b.txt', _oneConflict)],
      );
      expect(session.totalConflicts, 2);
      expect(session.allResolved, isFalse);

      session = session.replaceFile(
        0,
        session.files[0].withResolution(0, Resolution.theirs),
      );
      expect(session.resolvedConflicts, 1);
      expect(session.allResolved, isFalse);

      session = session.replaceFile(
        1,
        session.files[1].withResolution(0, Resolution.ours),
      );
      expect(session.allResolved, isTrue);
    });

    test('kind defaults to merge and dropStashRef to null', () {
      const s = MergeSession(branch: 'x', files: []);
      expect(s.kind, MergeKind.merge);
      expect(s.dropStashRef, isNull);
    });

    test('withFiles preserves kind and dropStashRef', () {
      const s = MergeSession(
        branch: 'x',
        files: [],
        kind: MergeKind.stash,
        dropStashRef: 'stash@{0}',
      );
      final s2 = s.withFiles(const []);
      expect(s2.kind, MergeKind.stash);
      expect(s2.dropStashRef, 'stash@{0}');
    });
  });
}
