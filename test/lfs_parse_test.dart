import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseCheckAttrLfs', () {
    test('keeps only paths whose filter is lfs', () {
      const raw =
          'a.psd\x00filter\x00lfs\x00'
          'b.txt\x00filter\x00unspecified\x00'
          'c.bin\x00filter\x00unset\x00';
      expect(parseCheckAttrLfs(raw), {'a.psd'});
    });

    test('paths with spaces, newlines and unicode survive', () {
      const raw =
          'art/my file.psd\x00filter\x00lfs\x00'
          'line\nbreak.bin\x00filter\x00lfs\x00'
          'зображення.png\x00filter\x00lfs\x00';
      expect(parseCheckAttrLfs(raw), {
        'art/my file.psd',
        'line\nbreak.bin',
        'зображення.png',
      });
    });

    test('empty and truncated input', () {
      expect(parseCheckAttrLfs(''), isEmpty);
      expect(parseCheckAttrLfs('a.psd\x00filter'), isEmpty);
    });
  });

  test('parseLfsVersion', () {
    expect(
      parseLfsVersion('git-lfs/3.5.1 (GitHub; darwin arm64; go 1.22.1)\n'),
      '3.5.1',
    );
    expect(parseLfsVersion(''), isNull);
    expect(parseLfsVersion("git: 'lfs' is not a git command."), isNull);
  });

  group('supportsCheckAttrSource', () {
    final cases = {
      'git version 2.39.5': false,
      'git version 2.39.5 (Apple Git-154)': false,
      'git version 2.40.0': true,
      'git version 2.40.0.windows.1': true,
      'git version 2.55.0': true,
      'git version 3.0.0': true,
      'git version 2': false,
      'garbage': false,
    };
    cases.forEach((v, want) {
      test(v, () => expect(supportsCheckAttrSource(v), want));
    });
  });

  group('lfsObjectsDir', () {
    test('defaults under the common dir, relative to the repo', () {
      expect(
        lfsObjectsDir(repoPath: '/r', commonDir: '.git'),
        p.join('/r', '.git', 'lfs', 'objects'),
      );
    });
    test('absolute common dir from a linked worktree', () {
      expect(
        lfsObjectsDir(repoPath: '/wt', commonDir: '/r/.git'),
        p.join('/r', '.git', 'lfs', 'objects'),
      );
    });
    test('relative lfs.storage resolves against the git dir', () {
      expect(
        lfsObjectsDir(repoPath: '/r', commonDir: '.git', lfsStorage: 'big'),
        p.join('/r', '.git', 'big', 'objects'),
      );
    });
    test('absolute lfs.storage is used as is', () {
      expect(
        lfsObjectsDir(repoPath: '/r', commonDir: '.git', lfsStorage: '/lfs'),
        p.join('/lfs', 'objects'),
      );
    });
  });

  test('lfsObjectPath fans out by the first two byte pairs', () {
    const oid =
        '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
    expect(lfsObjectPath('/o', oid), p.join('/o', '4d', '7a', oid));
  });

  group('formatLfsSize', () {
    final cases = {
      0: '0 B',
      1023: '1023 B',
      1024: '1.0 KB',
      1536: '1.5 KB',
      1048575: '1.0 MB',
      1048576: '1.0 MB',
      4404019: '4.2 MB',
      1073741824: '1.0 GB',
      1099511627776: '1.0 TB',
    };
    cases.forEach((bytes, want) {
      test('$bytes', () => expect(formatLfsSize(bytes), want));
    });
  });

  test('lfsInstallRoute', () {
    expect(lfsInstallRoute('macos'), LfsInstallRoute.homebrew);
    expect(lfsInstallRoute('windows'), LfsInstallRoute.gitForWindows);
    expect(lfsInstallRoute('linux'), LfsInstallRoute.packageManager);
  });

  test('parseGrepRevPaths strips the rev prefix', () {
    expect(parseGrepRevPaths('abc:a.psd\x00abc:dir/b c.bin\x00', 'abc'), {
      'a.psd',
      'dir/b c.bin',
    });
    expect(parseGrepRevPaths('', 'abc'), isEmpty);
  });

  test('parseBatchCheck keeps input order and marks missing', () {
    const raw =
        '1111111111111111111111111111111111111111 blob 130\n'
        'abc:gone.bin missing\n'
        '2222222222222222222222222222222222222222 tree 40\n';
    expect(parseBatchCheck(raw), [
      ('1111111111111111111111111111111111111111', 130),
      null,
      null, // not a blob
    ]);
  });

  test('parseCatFileBatch splits records by byte size', () {
    const body1 = 'hello\n';
    const body2 = 'wörld'; // 6 bytes in UTF-8
    const raw =
        'aaaa blob 6\n$body1\n'
        'bbbb blob 6\n$body2\n';
    expect(parseCatFileBatch(raw), {'aaaa': body1, 'bbbb': body2});
  });

  test('parseCatFileBatch stops at a malformed header', () {
    expect(parseCatFileBatch('aaaa blob 3\nabc\nnonsense\n'), {'aaaa': 'abc'});
  });
}
