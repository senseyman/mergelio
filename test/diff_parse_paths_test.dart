import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';

// Headers exactly as git 2.x prints them with default core.quotePath: a name
// with a space gets a trailing tab on its ---/+++ lines, and a non-ASCII or
// control-character name is C-quoted everywhere.
void main() {
  test('a name with a space loses the tab git appends', () {
    final files = parseUnifiedDiff(
      'diff --git a/a b.txt b/a b.txt\n'
      'new file mode 100644\n'
      '--- /dev/null\n'
      '+++ b/a b.txt\t\n'
      '@@ -0,0 +1 @@\n'
      '+y\n',
    );
    expect(files.single.path, 'a b.txt');
  });

  test('a quoted name is unquoted', () {
    final files = parseUnifiedDiff(
      'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n'
      'index 1..2 100644\n'
      '--- "a/caf\\303\\251.txt"\n'
      '+++ "b/caf\\303\\251.txt"\n'
      '@@ -1 +1 @@\n'
      '-x\n'
      '+y\n',
    );
    expect(files.single.path, 'café.txt');
  });

  test('a deleted quoted name is kept, under its old name', () {
    final files = parseUnifiedDiff(
      'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n'
      'deleted file mode 100644\n'
      '--- "a/caf\\303\\251.txt"\n'
      '+++ /dev/null\n'
      '@@ -1 +0,0 @@\n'
      '-x\n',
    );
    expect(files.single.path, 'café.txt');
    expect(files.single.status, GitChange.deleted);
  });

  test('a quoted rename unquotes both sides', () {
    final files = parseUnifiedDiff(
      'diff --git "a/\\303\\251.txt" "b/\\303\\251 2.txt"\n'
      'similarity index 100%\n'
      'rename from "\\303\\251.txt"\n'
      'rename to "\\303\\251 2.txt"\n',
    );
    expect(files.single.path, 'é 2.txt');
    expect(files.single.oldPath, 'é.txt');
  });

  test('a binary file whose name holds " b/" keeps its whole name', () {
    // No ---/+++ lines to correct the header, and the a/ and b/ halves are
    // the same name, so the header splits down the middle.
    final files = parseUnifiedDiff(
      'diff --git a/foo b/bar.png b/foo b/bar.png\n'
      'new file mode 100644\n'
      'index 0000000..1234567\n'
      'Binary files /dev/null and b/foo b/bar.png differ\n',
    );
    expect(files.single.path, 'foo b/bar.png');
    expect(files.single.binary, isTrue);
  });
}
