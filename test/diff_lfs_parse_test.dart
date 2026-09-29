import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';

const _a = '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
const _b = 'b7e2c1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2';
const _v = 'version https://git-lfs.github.com/spec/v1';

void main() {
  test('modified pointer → both sides, hunks kept', () {
    final f = parseUnifiedDiff('''
diff --git a/art.psd b/art.psd
index 1..2 100644
--- a/art.psd
+++ b/art.psd
@@ -1,3 +1,3 @@
 $_v
-oid sha256:$_a
-size 100
+oid sha256:$_b
+size 200
''').single;
    expect(f.lfs!.before!.size, 100);
    expect(f.lfs!.after!.oid, _b);
    expect(f.hunks, isNotEmpty);
    expect(lfsChangeKind(f), LfsChangeKind.modified);
  });

  test('added pointer', () {
    final f = parseUnifiedDiff('''
diff --git a/a.bin b/a.bin
new file mode 100644
--- /dev/null
+++ b/a.bin
@@ -0,0 +1,3 @@
+$_v
+oid sha256:$_a
+size 7
''').single;
    expect(f.lfs!.before, isNull);
    expect(f.lfs!.after!.size, 7);
    expect(lfsChangeKind(f), LfsChangeKind.added);
  });

  test('deleted pointer', () {
    final f = parseUnifiedDiff('''
diff --git a/a.bin b/a.bin
deleted file mode 100644
--- a/a.bin
+++ /dev/null
@@ -1,3 +0,0 @@
-$_v
-oid sha256:$_a
-size 7
''').single;
    expect(lfsChangeKind(f), LfsChangeKind.deleted);
  });

  test('text replaced by a pointer is moved into LFS', () {
    final f = parseUnifiedDiff('''
diff --git a/data.csv b/data.csv
--- a/data.csv
+++ b/data.csv
@@ -1,2 +1,3 @@
-a,b
-1,2
+$_v
+oid sha256:$_a
+size 9
''').single;
    expect(f.lfs!.before, isNull);
    expect(lfsChangeKind(f), LfsChangeKind.movedIn);
  });

  test('pointer replaced by text is moved out of LFS', () {
    final f = parseUnifiedDiff('''
diff --git a/data.csv b/data.csv
--- a/data.csv
+++ b/data.csv
@@ -1,3 +1,1 @@
-$_v
-oid sha256:$_a
-size 9
+a,b
''').single;
    expect(lfsChangeKind(f), LfsChangeKind.movedOut);
  });

  test('ordinary text diff has no lfs', () {
    final f = parseUnifiedDiff('''
diff --git a/a.txt b/a.txt
--- a/a.txt
+++ b/a.txt
@@ -1,2 +1,2 @@
 keep
-old
+new
''').single;
    expect(f.lfs, isNull);
  });

  test('binary entry has no lfs', () {
    final f = parseUnifiedDiff('''
diff --git a/i.png b/i.png
Binary files a/i.png and b/i.png differ
''').single;
    expect(f.binary, isTrue);
    expect(f.lfs, isNull);
  });

  test('quoted spec line in a larger file is not lfs', () {
    final f = parseUnifiedDiff('''
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -10,3 +10,4 @@
 $_v
 oid sha256:$_a
 size 7
+more docs
''').single;
    expect(f.lfs, isNull);
  });

  test('two hunks are never lfs', () {
    final f = parseUnifiedDiff('''
diff --git a/x b/x
--- a/x
+++ b/x
@@ -1,3 +1,3 @@
 $_v
-oid sha256:$_a
+oid sha256:$_b
 size 7
@@ -20,1 +20,1 @@
-a
+b
''').single;
    expect(f.lfs, isNull);
  });

  test('status survives for the kind mapping', () {
    final f = parseUnifiedDiff('''
diff --git a/a.bin b/a.bin
new file mode 100644
--- /dev/null
+++ b/a.bin
@@ -0,0 +1,3 @@
+$_v
+oid sha256:$_a
+size 7
''').single;
    expect(f.status, GitChange.added);
  });
}
