import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';

void main() {
  group('parseUnifiedDiff', () {
    test('parses a modified file with one hunk and line numbering', () {
      const raw = '''
diff --git a/foo.txt b/foo.txt
index e69de29..1234567 100644
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,4 @@
 context1
-removed
+added1
+added2
 context2
''';
      final files = parseUnifiedDiff(raw);
      expect(files, hasLength(1));
      final f = files.single;
      expect(f.path, 'foo.txt');
      expect(f.status, GitChange.modified);
      expect(f.hunks, hasLength(1));

      final h = f.hunks.single;
      expect(h.oldStart, 1);
      expect(h.newStart, 1);
      expect(h.lines.map((l) => l.type), [
        DiffLineType.context,
        DiffLineType.del,
        DiffLineType.add,
        DiffLineType.add,
        DiffLineType.context,
      ]);

      final ctx1 = h.lines.first;
      expect(ctx1.oldNo, 1);
      expect(ctx1.newNo, 1);
      expect(ctx1.text, 'context1');

      final del = h.lines[1];
      expect(del.oldNo, 2);
      expect(del.newNo, isNull);

      final add1 = h.lines[2];
      expect(add1.oldNo, isNull);
      expect(add1.newNo, 2);

      final ctx2 = h.lines.last;
      expect(ctx2.oldNo, 3);
      expect(ctx2.newNo, 4);
    });

    test('marks a new file as added', () {
      const raw = '''
diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000..89b24ec
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+one
+two
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.status, GitChange.added);
      expect(f.path, 'new.txt');
      expect(
        f.hunks.single.lines.every((l) => l.type == DiffLineType.add),
        isTrue,
      );
    });

    test('marks a deleted file', () {
      const raw = '''
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
index 89b24ec..0000000
--- a/gone.txt
+++ /dev/null
@@ -1,1 +0,0 @@
-bye
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.status, GitChange.deleted);
      expect(f.path, 'gone.txt');
    });

    test('captures a rename with its old path', () {
      const raw = '''
diff --git a/old.txt b/new.txt
similarity index 100%
rename from old.txt
rename to new.txt
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.status, GitChange.renamed);
      expect(f.path, 'new.txt');
      expect(f.oldPath, 'old.txt');
    });

    test('flags a binary file and leaves no hunks', () {
      const raw = '''
diff --git a/img.png b/img.png
index 0000000..1111111 100644
Binary files a/img.png and b/img.png differ
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.binary, isTrue);
      expect(f.hunks, isEmpty);
    });

    test('parses multiple files in one diff', () {
      const raw = '''
diff --git a/a.txt b/a.txt
index 1..2 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-a
+A
diff --git a/b.txt b/b.txt
index 3..4 100644
--- a/b.txt
+++ b/b.txt
@@ -1 +1 @@
-b
+B
''';
      final files = parseUnifiedDiff(raw);
      expect(files.map((f) => f.path), ['a.txt', 'b.txt']);
    });

    test('hunk body lines that look like file headers are kept', () {
      // A deleted line whose content is "-- old" is emitted as "--- old";
      // an added "++ x" as "+++ x". These must stay hunk content.
      const raw = '''
diff --git a/q.sql b/q.sql
index 1..2 100644
--- a/q.sql
+++ b/q.sql
@@ -1,2 +1,2 @@
 SELECT 1;
--- old comment
+-- new comment
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.path, 'q.sql');
      final lines = f.hunks.single.lines;
      expect(lines.map((l) => l.type), [
        DiffLineType.context,
        DiffLineType.del,
        DiffLineType.add,
      ]);
      expect(lines[1].text, '-- old comment');
      expect(lines[2].text, '-- new comment');
    });

    test('honours "No newline at end of file" without emitting a line', () {
      const raw = '''
diff --git a/n.txt b/n.txt
index 1..2 100644
--- a/n.txt
+++ b/n.txt
@@ -1 +1 @@
-old
\\ No newline at end of file
+new
\\ No newline at end of file
''';
      final f = parseUnifiedDiff(raw).single;
      expect(f.hunks.single.lines.map((l) => l.type), [
        DiffLineType.del,
        DiffLineType.add,
      ]);
    });
  });
}
