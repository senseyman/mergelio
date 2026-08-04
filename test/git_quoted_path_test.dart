// Git prints a path C-quoted when it holds a character that would confuse a
// line-based reader. Every command we read line by line has to undo that.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/quoted_path.dart';

void main() {
  test('an ordinary name is returned as it is', () {
    expect(unquoteGitPath('lib/main.dart'), 'lib/main.dart');
  });

  test('a name that only contains spaces is not quoted by git', () {
    expect(unquoteGitPath('we ird.log'), 'we ird.log');
  });

  test('an escaped quote and backslash come back as themselves', () {
    expect(unquoteGitPath(r'"quo\"te.log"'), 'quo"te.log');
    expect(unquoteGitPath(r'"back\\slash.log"'), r'back\slash.log');
  });

  test('control-character escapes are decoded', () {
    expect(unquoteGitPath(r'"two\nlines.txt"'), 'two\nlines.txt');
    expect(unquoteGitPath(r'"a\tb.txt"'), 'a\tb.txt');
  });

  test('octal escapes are decoded as UTF-8 bytes', () {
    expect(unquoteGitPath(r'"\303\274ber.txt"'), 'über.txt');
  });

  test('a lone quote is not treated as a quoted name', () {
    expect(unquoteGitPath('"unterminated'), '"unterminated');
  });
}
