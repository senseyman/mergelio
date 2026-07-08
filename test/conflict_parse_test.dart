import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';

void main() {
  group('parseConflicts', () {
    test('splits context blocks and conflict hunks', () {
      const raw = '''
top
<<<<<<< HEAD
our line
=======
their line
>>>>>>> feature
bottom
''';
      final parts = parseConflicts(raw);
      expect(parts, hasLength(3));
      expect((parts[0] as ContextBlock).lines, ['top']);
      final hunk = parts[1] as ConflictHunk;
      expect(hunk.ours, ['our line']);
      expect(hunk.theirs, ['their line']);
      expect((parts[2] as ContextBlock).lines, ['bottom']);
    });

    test('handles multiple hunks and multi-line sides', () {
      const raw = '''
<<<<<<< HEAD
a1
a2
=======
b1
>>>>>>> x
mid
<<<<<<< HEAD
=======
c1
>>>>>>> x
''';
      final parts = parseConflicts(raw);
      final hunks = parts.whereType<ConflictHunk>().toList();
      expect(hunks, hasLength(2));
      expect(hunks[0].ours, ['a1', 'a2']);
      expect(hunks[0].theirs, ['b1']);
      expect(hunks[1].ours, isEmpty);
      expect(hunks[1].theirs, ['c1']);
    });

    test('diff3 style: the ||||||| base section is dropped from ours', () {
      const raw = '''
top
<<<<<<< HEAD
our line
||||||| base
original line
=======
their line
>>>>>>> feature
''';
      final hunk = parseConflicts(raw).whereType<ConflictHunk>().single;
      expect(hunk.ours, ['our line']); // base section excluded
      expect(hunk.theirs, ['their line']);
    });

    test('a file with no markers is one context block', () {
      final parts = parseConflicts('plain\ntext\n');
      expect(parts, hasLength(1));
      expect(parts.single, isA<ContextBlock>());
    });

    test('hasConflictMarkers detects markers', () {
      expect(
        hasConflictMarkers('<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> b\n'),
        isTrue,
      );
      expect(hasConflictMarkers('no markers here'), isFalse);
    });
  });

  group('resolveConflicts', () {
    ConflictHunk hunk() => ConflictHunk(ours: ['O'], theirs: ['T']);

    test('accept ours / theirs / both', () {
      final parts = [
        ContextBlock(['top']),
        hunk(),
        ContextBlock(['end']),
      ];
      expect(resolveConflicts(parts, {1: Resolution.ours}), 'top\nO\nend\n');
      expect(resolveConflicts(parts, {1: Resolution.theirs}), 'top\nT\nend\n');
      expect(resolveConflicts(parts, {1: Resolution.both}), 'top\nO\nT\nend\n');
    });

    test('a custom edit replaces the hunk body', () {
      final parts = [hunk()];
      expect(
        resolveConflicts(
          parts,
          {0: Resolution.custom},
          custom: {
            0: ['X', 'Y'],
          },
        ),
        'X\nY\n',
      );
    });

    test('an unresolved hunk re-emits the markers', () {
      final parts = [hunk()];
      final out = resolveConflicts(parts, const {});
      expect(hasConflictMarkers(out), isTrue);
    });
  });
}
