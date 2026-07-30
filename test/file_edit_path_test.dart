import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/file_edit.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isRepoRelativePath', () {
    test('accepts ordinary repo-relative paths', () {
      expect(isRepoRelativePath('a.txt'), isTrue);
      expect(isRepoRelativePath('lib/src/a.dart'), isTrue);
      expect(isRepoRelativePath('a b/c d.txt'), isTrue);
      expect(isRepoRelativePath('..a/b..'), isTrue); // dots inside names
      expect(isRepoRelativePath('a/.hidden'), isTrue);
    });

    test('rejects paths that escape or leave the repository', () {
      expect(isRepoRelativePath(''), isFalse);
      expect(isRepoRelativePath('../outside.txt'), isFalse);
      expect(isRepoRelativePath('a/../../outside.txt'), isFalse);
      expect(isRepoRelativePath('a/..'), isFalse);
      expect(isRepoRelativePath(r'a\..\outside.txt'), isFalse);
      expect(isRepoRelativePath('/etc/passwd'), isFalse);
      expect(isRepoRelativePath(r'\server\share'), isFalse);
      expect(isRepoRelativePath(r'C:\Windows\a.txt'), isFalse);
      expect(isRepoRelativePath('C:/Windows/a.txt'), isFalse);
    });
  });

  group('isWithinOrEqual', () {
    test('accepts the root itself and paths beneath it', () {
      expect(isWithinOrEqual('/x/repo', '/x/repo', context: p.posix), isTrue);
      expect(
        isWithinOrEqual('/x/repo', '/x/repo/lib/a.dart', context: p.posix),
        isTrue,
      );
    });

    test('rejects siblings sharing the root as a name prefix', () {
      expect(
        isWithinOrEqual('/x/repo', '/x/repo-evil/a', context: p.posix),
        isFalse,
      );
      expect(
        isWithinOrEqual('/x/repo', '/x/other/a', context: p.posix),
        isFalse,
      );
    });

    test('compares with Windows separators and drive letters', () {
      expect(
        isWithinOrEqual(r'C:\repo', r'C:\repo\lib\a.dart', context: p.windows),
        isTrue,
      );
      expect(
        isWithinOrEqual(r'C:\repo', r'C:\repo-evil\a.dart', context: p.windows),
        isFalse,
      );
      expect(
        isWithinOrEqual(r'C:\repo', r'D:\repo\a.dart', context: p.windows),
        isFalse,
      );
    });
  });

  group('isInsideRepo', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mergelio_inside_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('accepts a regular file inside the repo', () {
      final repo = Directory('${tmp.path}/repo')..createSync();
      final f = File('${repo.path}/a.txt')..writeAsStringSync('x');
      expect(isInsideRepo(repo.path, f.path), isTrue);
    });

    test('rejects a symlink that points outside the repo', () {
      final repo = Directory('${tmp.path}/repo')..createSync();
      final outside = File('${tmp.path}/secret.txt')..writeAsStringSync('s');
      final link = Link('${repo.path}/inside.txt')..createSync(outside.path);
      expect(isInsideRepo(repo.path, link.path), isFalse);
    });

    test('rejects a file in a sibling directory named like the repo', () {
      final repo = Directory('${tmp.path}/repo')..createSync();
      final evil = Directory('${tmp.path}/repo-evil')..createSync();
      final f = File('${evil.path}/a.txt')..writeAsStringSync('x');
      expect(isInsideRepo(repo.path, f.path), isFalse);
    });

    test('rejects a path that cannot be resolved', () {
      final repo = Directory('${tmp.path}/repo')..createSync();
      expect(isInsideRepo(repo.path, '${repo.path}/missing.txt'), isFalse);
    });
  });
}
