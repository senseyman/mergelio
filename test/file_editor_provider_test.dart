import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/file_edit.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_editprov_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<EditableFile> load({String path = 'a.txt', String? commitSha}) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c.read(
      editableFileProvider(
        DiffTarget(repoPath: dir.path, path: path, commitSha: commitSha),
      ).future,
    );
  }

  test('loads a text file with the timestamp it was read at', () async {
    File('${dir.path}/a.txt').writeAsStringSync('hello\nthere\n');
    final f = await load();

    expect(f.canEdit, isTrue);
    expect(f.text, 'hello\nthere\n');
    expect(f.loadedAt, isNotNull);
  });

  test('refuses a binary file', () async {
    File('${dir.path}/a.txt').writeAsBytesSync([0x68, 0x00, 0x69]);
    final f = await load();

    expect(f.canEdit, isFalse);
    expect(f.blocker, contains('Binary'));
  });

  test('refuses a file that is not in the working tree', () async {
    final f = await load(path: 'missing.txt');

    expect(f.canEdit, isFalse);
    expect(f.blocker, contains('working tree'));
  });

  test('refuses a commit diff', () async {
    File('${dir.path}/a.txt').writeAsStringSync('hello\n');
    final f = await load(commitSha: 'abc1234');

    expect(f.canEdit, isFalse);
    expect(f.blocker, contains('uncommitted'));
  });

  test('refuses a file past the size cap', () async {
    File(
      '${dir.path}/a.txt',
    ).writeAsBytesSync(List<int>.filled(maxEditableBytes + 1, 0x61));
    final f = await load();

    expect(f.canEdit, isFalse);
    expect(f.blocker, contains('too large'));
  });

  test('keeps a file with malformed bytes editable', () async {
    File('${dir.path}/a.txt').writeAsBytesSync([0x61, 0xC3, 0x28, 0x62]);
    final f = await load();

    expect(f.canEdit, isTrue);
    expect(f.text, startsWith('a'));
  });
}
