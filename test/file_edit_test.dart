import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/file_edit.dart';

void main() {
  group('looksBinary', () {
    test('plain text is not binary', () {
      expect(looksBinary('hello\nworld\n'.codeUnits), isFalse);
    });

    test('empty content is not binary', () {
      expect(looksBinary(const []), isFalse);
    });

    test('a NUL byte marks it binary', () {
      expect(looksBinary([0x68, 0x00, 0x69]), isTrue);
    });

    test('only the first block is sniffed', () {
      final bytes = List<int>.filled(9000, 0x61, growable: true)..add(0x00);
      expect(looksBinary(bytes), isFalse);
    });
  });

  group('fileEditBlocker', () {
    String? blocker({
      bool isWorkingTree = true,
      bool exists = true,
      bool binary = false,
      int sizeBytes = 10,
    }) => fileEditBlocker(
      isWorkingTree: isWorkingTree,
      exists: exists,
      binary: binary,
      sizeBytes: sizeBytes,
    );

    test('an ordinary working-tree file is editable', () {
      expect(blocker(), isNull);
    });

    test('a commit diff is not editable', () {
      expect(blocker(isWorkingTree: false), isNotNull);
    });

    test('a file missing from the working tree is not editable', () {
      expect(blocker(exists: false), isNotNull);
    });

    test('a binary file is not editable', () {
      expect(blocker(binary: true), isNotNull);
    });

    test('a file past the size cap is not editable', () {
      expect(blocker(sizeBytes: maxEditableBytes + 1), isNotNull);
      expect(blocker(sizeBytes: maxEditableBytes), isNull);
    });
  });

  group('fileChangedSince', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mergelio_edit_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('an untouched file has not changed', () async {
      final f = File('${dir.path}/a.txt')..writeAsStringSync('one\n');
      final loadedAt = await f.lastModified();
      expect(await fileChangedSince(f, loadedAt), isFalse);
    });

    test('a file written after loading has changed', () async {
      final f = File('${dir.path}/a.txt')..writeAsStringSync('one\n');
      final loadedAt = await f.lastModified();
      await f.setLastModified(loadedAt.add(const Duration(seconds: 2)));
      expect(await fileChangedSince(f, loadedAt), isTrue);
    });

    test('a file that never loaded a timestamp has not changed', () async {
      final f = File('${dir.path}/a.txt')..writeAsStringSync('one\n');
      expect(await fileChangedSince(f, null), isFalse);
    });

    test('a file deleted since loading is not reported as changed', () async {
      final f = File('${dir.path}/gone.txt');
      expect(await fileChangedSince(f, DateTime(2000)), isFalse);
    });
  });
}
