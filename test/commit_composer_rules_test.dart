import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/commit_message.dart';

Issue _issue(int n, String title) => Issue(
  number: n,
  title: title,
  state: IssueState.open,
  author: const ForgeUser(login: 'a'),
);

void main() {
  group('stripCommentLines', () {
    test('drops comment lines and the blank lines they leave behind', () {
      const t = '\n# Subject: what changed\n\n# Why:\n';
      expect(stripCommentLines(t), '');
    });

    test('keeps text around comments, collapsing blank runs', () {
      const t = 'feat: \n# hint\n\n\n\nBody line\n# more\n';
      expect(stripCommentLines(t), 'feat:\n\nBody line');
    });

    test('a custom comment char is honoured and # survives', () {
      expect(
        stripCommentLines('; hint\n#12 is fixed', commentChar: ';'),
        '#12 is fixed',
      );
    });

    test('everything below the scissors line is cut', () {
      const t =
          'Subject\n'
          '# ------------------------ >8 ------------------------\n'
          'diff --git a b\n';
      expect(stripCommentLines(t), 'Subject');
    });

    test('CRLF is normalised', () {
      expect(stripCommentLines('A\r\n# c\r\n\r\nB\r\n'), 'A\n\nB');
    });
  });

  group('isUntouchedTemplate', () {
    test('the template text itself is untouched', () {
      expect(
        isUntouchedTemplate('Fix: \n\nWhy:', '# x\nFix:\n\nWhy:\n'),
        isTrue,
      );
    });

    test('an edited message is not', () {
      expect(isUntouchedTemplate('Fix: parser', 'Fix:\n'), isFalse);
    });

    test('an empty template never matches', () {
      expect(isUntouchedTemplate('', '# only comments\n'), isFalse);
    });
  });

  group('conventional subjects', () {
    test('type, scope and breaking compose a subject', () {
      expect(
        formatConventionalSubject((
          type: 'feat',
          scope: 'diff',
          breaking: true,
          description: 'show binary sizes ',
        )),
        'feat(diff)!: show binary sizes',
      );
    });

    test('no scope drops the parentheses', () {
      expect(
        formatConventionalSubject((
          type: 'fix',
          scope: '  ',
          breaking: false,
          description: 'x',
        )),
        'fix: x',
      );
    });

    test('no type leaves the description alone', () {
      expect(
        formatConventionalSubject((
          type: '',
          scope: 'ui',
          breaking: true,
          description: 'fixup! thing',
        )),
        'fixup! thing',
      );
    });

    test('a conventional subject parses back into its parts', () {
      final s = parseConventionalSubject('fix(git)!: stop at break');
      expect(s, isNotNull);
      expect(s!.type, 'fix');
      expect(s.scope, 'git');
      expect(s.breaking, isTrue);
      expect(s.description, 'stop at break');
    });

    test('an unknown type or plain text does not parse', () {
      expect(parseConventionalSubject('wip: stuff'), isNull);
      expect(parseConventionalSubject('Fix the parser'), isNull);
      expect(parseConventionalSubject('fixup! feat: x'), isNull);
    });

    test('parse then format round-trips', () {
      const raw = 'refactor(state): split store';
      expect(formatConventionalSubject(parseConventionalSubject(raw)!), raw);
    });
  });

  group('subjectLength', () {
    test('counts characters, not UTF-16 units', () {
      expect(subjectLength('fix: 🎉'), 6);
      expect(subjectLength('виправлено'), 10);
    });
  });

  group('wrapBody', () {
    test('rewraps a prose paragraph to the width', () {
      expect(
        wrapBody('one two three four five six', 9),
        'one two\nthree\nfour five\nsix',
      );
    });

    test('joins a ragged paragraph before wrapping', () {
      expect(wrapBody('a b\nc d', 20), 'a b c d');
    });

    test('keeps paragraphs apart', () {
      expect(wrapBody('a b\n\nc d', 3), 'a b\n\nc d');
    });

    test('leaves lists, quotes, indented code and fences intact', () {
      const text =
          '- a long list item that runs past the width\n'
          '1. numbered item that also runs past the width\n'
          '> a quoted line that runs past the width\n'
          '    indented code that runs past the width\n'
          '```\n'
          'fenced code that runs past the width\n'
          '```';
      expect(wrapBody(text, 10), text);
    });

    test('leaves trailer lines intact', () {
      const text = 'Co-authored-by: A Very Long Name <a.very.long@example.com>';
      expect(wrapBody(text, 10), text);
    });

    test('a word longer than the width sits on its own line', () {
      expect(
        wrapBody('see https://example.com/very/long/url ok', 10),
        'see\nhttps://example.com/very/long/url\nok',
      );
    });
  });

  group('trailers', () {
    test('splitList trims and drops empties', () {
      expect(splitList(' a , ,b,'), ['a', 'b']);
    });

    test('a bare number is an issue reference', () {
      expect(normaliseIssueRef('12'), '#12');
      expect(normaliseIssueRef(' #12 '), '#12');
      expect(normaliseIssueRef('JIRA-4'), 'JIRA-4');
    });

    test('buildTrailers orders refs, fixes, then co-authors', () {
      expect(
        buildTrailers(refs: ['3'], fixes: ['#4', '5'], coauthors: ['A <a@x>']),
        [
          (key: 'Refs', value: '#3'),
          (key: 'Fixes', value: '#4'),
          (key: 'Fixes', value: '#5'),
          (key: 'Co-authored-by', value: 'A <a@x>'),
        ],
      );
    });

    test('a message without trailers is subject and body', () {
      expect(buildCommitMessage(' S ', ' B '), 'S\n\nB');
    });

    test('trailers follow the body after a blank line', () {
      expect(
        buildCommitMessage('S', 'Body', trailers: [(key: 'Refs', value: '#1')]),
        'S\n\nBody\n\nRefs: #1',
      );
    });

    test('trailers follow the subject when there is no body', () {
      expect(
        buildCommitMessage('S', '', trailers: [(key: 'Refs', value: '#1')]),
        'S\n\nRefs: #1',
      );
    });

    test('trailers join a trailer block the body already ends with', () {
      expect(
        buildCommitMessage(
          'S',
          'Body\n\nReviewed-by: R <r@x>',
          trailers: [(key: 'Fixes', value: '#2')],
        ),
        'S\n\nBody\n\nReviewed-by: R <r@x>\nFixes: #2',
      );
    });
  });

  group('pushRecent', () {
    test('puts the newest first, dedupes, and caps', () {
      expect(pushRecent(['b', 'a'], 'a', cap: 2), ['a', 'b']);
      expect(pushRecent(['b', 'a'], 'c', cap: 2), ['c', 'b']);
    });

    test('ignores an empty message', () {
      expect(pushRecent(['a'], '  '), ['a']);
    });

    test('trims what it stores', () {
      expect(pushRecent(const [], ' x \n'), ['x']);
    });
  });

  group('issue completion', () {
    test('currentToken is what follows the last comma', () {
      expect(currentToken('#1, #2'), '#2');
      expect(currentToken('#1, '), '');
      expect(currentToken('  #4'), '#4');
    });

    test('replaceCurrentToken swaps only the last entry', () {
      expect(replaceCurrentToken('#1, #2', '#23'), '#1, #23');
      expect(replaceCurrentToken('', '#7'), '#7');
      expect(replaceCurrentToken('#1,', '#7'), '#1, #7');
    });

    final issues = [
      _issue(12, 'Crash on start'),
      _issue(120, 'Docs'),
      _issue(3, 'Slow diff'),
    ];

    test('a number matches by prefix', () {
      expect(matchIssues(issues, '#12').map((i) => i.number), [12, 120]);
    });

    test('text matches the title, case-insensitively', () {
      expect(matchIssues(issues, 'crash').map((i) => i.number), [12]);
    });

    test('an empty query offers every issue', () {
      expect(matchIssues(issues, ''), hasLength(3));
    });
  });
}
