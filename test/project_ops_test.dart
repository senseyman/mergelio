// Creating, renaming and deleting files from the navigator. Every operation
// is fenced off to the opened repository and refuses to clobber what is
// already there unless the user said so.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/project_ops.dart';
import 'package:path/path.dart' as p;

void main() {
  group('name validation', () {
    test('a plain name is accepted', () {
      expect(entryNameBlocker('notes.txt'), isNull);
    });

    test('an empty or blank name is refused', () {
      expect(entryNameBlocker(''), isNotNull);
      expect(entryNameBlocker('   '), isNotNull);
    });

    test('a name carrying a path separator is refused', () {
      expect(entryNameBlocker('a/b.txt'), isNotNull);
      expect(entryNameBlocker(r'a\b.txt'), isNotNull);
    });

    test('the directory shorthands are refused', () {
      expect(entryNameBlocker('.'), isNotNull);
      expect(entryNameBlocker('..'), isNotNull);
    });

    test('a windows device name is refused on every platform', () {
      // These are unusable on Windows and a repository is shared across
      // platforms, so they are refused everywhere rather than creating a
      // repository someone else cannot check out.
      expect(entryNameBlocker('CON'), isNotNull);
      expect(entryNameBlocker('lpt1.txt'), isNotNull);
      expect(entryNameBlocker('console.txt'), isNull);
    });

    test('a name windows cannot write is refused', () {
      expect(entryNameBlocker('a:b'), isNotNull);
      expect(entryNameBlocker('what?'), isNotNull);
      expect(entryNameBlocker('trailing.'), isNotNull);
    });

    test('git’s own directory is refused', () {
      expect(entryNameBlocker('.git'), isNotNull);
    });
  });

  group('on disk', () {
    late Directory repo;
    late ProjectOps ops;

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('mergelio_ops');
      ops = ProjectOps(repo.path);
      await Directory(p.join(repo.path, 'lib')).create();
      await File(p.join(repo.path, 'lib', 'main.dart')).writeAsString('void');
    });

    tearDown(() async {
      if (repo.existsSync()) await repo.delete(recursive: true);
    });

    test('a new file is created empty in the chosen directory', () async {
      final r = await ops.createFile('lib', 'extra.dart');

      expect(r.ok, isTrue);
      expect(r.path, 'lib/extra.dart');
      expect(File(p.join(repo.path, 'lib', 'extra.dart')).existsSync(), isTrue);
    });

    test('a new file at the repository root needs no directory', () async {
      final r = await ops.createFile('', 'TODO.md');

      expect(r.ok, isTrue);
      expect(r.path, 'TODO.md');
    });

    test('a new folder is created', () async {
      final r = await ops.createFolder('lib', 'ui');

      expect(r.ok, isTrue);
      expect(Directory(p.join(repo.path, 'lib', 'ui')).existsSync(), isTrue);
    });

    test('creating over an existing entry is refused', () async {
      final r = await ops.createFile('lib', 'main.dart');

      expect(r.ok, isFalse);
      expect(r.error, contains('already exists'));
      // The file that was there is untouched.
      expect(
        await File(p.join(repo.path, 'lib', 'main.dart')).readAsString(),
        'void',
      );
    });

    test('an invalid name is refused before disk is touched', () async {
      final r = await ops.createFile('lib', '../escape.dart');

      expect(r.ok, isFalse);
      expect(File(p.join(repo.path, 'escape.dart')).existsSync(), isFalse);
    });

    test('a directory outside the repository is refused', () async {
      final r = await ops.createFile('../..', 'escape.txt');

      expect(r.ok, isFalse);
    });

    test('renaming moves the entry and reports the new path', () async {
      final r = await ops.rename('lib/main.dart', 'app.dart');

      expect(r.ok, isTrue);
      expect(r.path, 'lib/app.dart');
      expect(File(p.join(repo.path, 'lib', 'app.dart')).existsSync(), isTrue);
      expect(File(p.join(repo.path, 'lib', 'main.dart')).existsSync(), isFalse);
    });

    test('renaming a directory works too', () async {
      final r = await ops.rename('lib', 'src');

      expect(r.ok, isTrue);
      expect(Directory(p.join(repo.path, 'src')).existsSync(), isTrue);
    });

    test('renaming onto an existing entry is refused', () async {
      await File(p.join(repo.path, 'lib', 'app.dart')).writeAsString('other');

      final r = await ops.rename('lib/main.dart', 'app.dart');

      expect(r.ok, isFalse);
      expect(r.error, contains('already exists'));
      expect(
        await File(p.join(repo.path, 'lib', 'app.dart')).readAsString(),
        'other',
      );
    });

    test('renaming something that is not there is refused', () async {
      final r = await ops.rename('lib/ghost.dart', 'app.dart');

      expect(r.ok, isFalse);
    });

    test('deleting removes the file from disk', () async {
      final r = await ops.delete('lib/main.dart');

      expect(r.ok, isTrue);
      expect(File(p.join(repo.path, 'lib', 'main.dart')).existsSync(), isFalse);
    });

    test('deleting a directory takes what is inside it', () async {
      final r = await ops.delete('lib');

      expect(r.ok, isTrue);
      expect(Directory(p.join(repo.path, 'lib')).existsSync(), isFalse);
    });

    test('deleting outside the repository is refused', () async {
      final outside = await Directory.systemTemp.createTemp('mergelio_out');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });
      final victim = File(p.join(outside.path, 'victim.txt'));
      await victim.writeAsString('keep me');

      final r = await ops.delete('../${p.basename(outside.path)}/victim.txt');

      expect(r.ok, isFalse);
      expect(victim.existsSync(), isTrue);
    });

    test('a symlink pointing out of the repository is refused', () async {
      final outside = await Directory.systemTemp.createTemp('mergelio_out');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });
      final victim = File(p.join(outside.path, 'victim.txt'));
      await victim.writeAsString('keep me');
      await Link(p.join(repo.path, 'escape')).create(outside.path);

      final r = await ops.delete('escape/victim.txt');

      expect(r.ok, isFalse);
      expect(victim.existsSync(), isTrue);
    });

    test('git’s own directory is off limits', () async {
      await Directory(p.join(repo.path, '.git')).create();

      expect((await ops.delete('.git')).ok, isFalse);
      expect((await ops.createFile('.git', 'HEAD')).ok, isFalse);
      expect(Directory(p.join(repo.path, '.git')).existsSync(), isTrue);
    });
  });
}
