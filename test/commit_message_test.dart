import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/commit_message.dart';

void main() {
  group('splitCommitMessage', () {
    test('a subject-only message has no description', () {
      final m = splitCommitMessage('Fix the parser');
      expect(m.summary, 'Fix the parser');
      expect(m.description, '');
    });

    test('the first line is the summary, the rest the description', () {
      final m = splitCommitMessage('Fix the parser\n\nIt choked on tabs.\n');
      expect(m.summary, 'Fix the parser');
      expect(m.description, 'It choked on tabs.');
    });

    test('blank lines inside the description are kept', () {
      final m = splitCommitMessage('Subject\n\nOne\n\nTwo\n');
      expect(m.description, 'One\n\nTwo');
    });

    test('CRLF line endings are normalised away', () {
      final m = splitCommitMessage('Subject\r\n\r\nBody\r\n');
      expect(m.summary, 'Subject');
      expect(m.description, 'Body');
    });

    test('a description not separated by a blank line is still read', () {
      final m = splitCommitMessage('Subject\nBody');
      expect(m.summary, 'Subject');
      expect(m.description, 'Body');
    });

    test('an empty message splits into two empty parts', () {
      final m = splitCommitMessage('');
      expect(m.summary, '');
      expect(m.description, '');
    });
  });

  group('joinCommitMessage', () {
    test('an empty description yields the summary alone', () {
      expect(joinCommitMessage('Subject', ''), 'Subject');
    });

    test('a description is separated from the summary by a blank line', () {
      expect(joinCommitMessage('Subject', 'Body'), 'Subject\n\nBody');
    });

    test('surrounding whitespace is trimmed off both parts', () {
      expect(
        joinCommitMessage('  Subject  ', '\n Body \n\n'),
        'Subject\n\nBody',
      );
    });

    test('a whitespace-only description is dropped', () {
      expect(joinCommitMessage('Subject', '   \n  '), 'Subject');
    });
  });

  test('splitting then joining round-trips a full message', () {
    const original = 'Subject line\n\nParagraph one.\n\nParagraph two.';
    final m = splitCommitMessage(original);
    expect(joinCommitMessage(m.summary, m.description), original);
  });
}
