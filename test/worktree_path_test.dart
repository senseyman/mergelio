import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/path_key.dart';

void main() {
  test('trailing separators do not change identity', () {
    expect(samePath('/home/u/repo', '/home/u/repo/'), isTrue);
    expect(samePath('/home/u/repo//', '/home/u/repo'), isTrue);
  });

  test('different directories stay different', () {
    expect(samePath('/home/u/repo', '/home/u/repo-login'), isFalse);
  });

  test('backslashes normalise to forward slashes', () {
    expect(samePath(r'C:\code\repo', 'C:/code/repo'), isTrue);
  });

  test('case folds on macOS and Windows only', () {
    final a = samePath('/home/u/Repo', '/home/u/repo');
    expect(a, Platform.isMacOS || Platform.isWindows);
  });

  test('resolves symlinks so two spellings of one directory match', () async {
    final real = await Directory.systemTemp.createTemp('mergelio_pathkey_');
    final link = Link('${real.path}_link');
    await link.create(real.path);
    try {
      expect(samePath(real.path, link.path), isTrue);
    } finally {
      await link.delete();
      await real.delete(recursive: true);
    }
  });

  test('a path that does not exist still normalises without throwing', () {
    expect(samePath('/definitely/not/here', '/definitely/not/here/'), isTrue);
  });

  test(
    'a path that does not exist yet is keyed against its real parent',
    () async {
      final real = await Directory.systemTemp.createTemp('mergelio_deep_');
      final link = Link('${real.path}_link');
      await link.create(real.path);
      try {
        // Nothing at either spelling of `child` exists, but the parent does and
        // is reached through a symlink, so both must key the same.
        expect(samePath('${link.path}/child', '${real.path}/child'), isTrue);
        expect(
          samePath('${link.path}/a/b/c', '${real.path}/a/b/c'),
          isTrue,
          reason:
              'several missing segments still resolve at the deepest parent',
        );
        expect(samePath('${link.path}/child', '${real.path}/other'), isFalse);
      } finally {
        await link.delete();
        await real.delete(recursive: true);
      }
    },
  );
}
