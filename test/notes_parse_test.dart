import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/notes.dart';

void main() {
  group('parseNoteIndex', () {
    test('no notes ref lists nothing', () {
      expect(parseNoteIndex(''), isEmpty);
    });

    test('maps each annotated commit to its note blob', () {
      final index = parseNoteIndex(
        '4caf81228fbdb9e54041e34cfec1537d0a0572fb '
        'a6df318300536269b1332e4f39f16e4fc3748d98\n'
        'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 '
        '11bb9e345d88e41c28d5cba1198b35ad86ac5da5\n',
      );
      expect(index, {
        'a6df318300536269b1332e4f39f16e4fc3748d98':
            '4caf81228fbdb9e54041e34cfec1537d0a0572fb',
        '11bb9e345d88e41c28d5cba1198b35ad86ac5da5':
            'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391',
      });
    });

    test('skips lines that are not a pair of object names', () {
      final index = parseNoteIndex(
        'warning: something\n'
        '\n'
        'aaaa bbbb cccc\n'
        '4caf81228fbdb9e54041e34cfec1537d0a0572fb '
        'a6df318300536269b1332e4f39f16e4fc3748d98\r\n',
      );
      expect(index.keys, ['a6df318300536269b1332e4f39f16e4fc3748d98']);
    });
  });

  group('normalizeNote', () {
    test('tidies text the way git stores it', () {
      expect(normalizeNote('\n\n  a  \n\n\n\nb\t\r\n\n'), '  a\n\nb');
    });

    test('blank text is no note', () {
      expect(normalizeNote(' \n\t\n'), '');
    });
  });

  group('notesRefsSignature', () {
    test('keeps only the notes refs of a ref listing', () {
      expect(
        notesRefsSignature(
          'aaa refs/heads/main\n'
          'bbb refs/notes/commits\n'
          'ccc refs/tags/v1\n'
          'ddd refs/notes/review\n'
          '\nHEAD aaa',
        ),
        'bbb refs/notes/commits\nddd refs/notes/review',
      );
    });

    test('a repository without notes has an empty signature', () {
      expect(notesRefsSignature('aaa refs/heads/main\n\nHEAD aaa'), '');
    });
  });
}
