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

  group('lfsAttributePattern', () {
    // Plain enough to mean the same to Dart and to git's extended regex.
    final re = RegExp(lfsAttributePattern);
    test('matches lines that route files through LFS', () {
      expect(re.hasMatch('*.psd filter=lfs diff=lfs merge=lfs -text'), isTrue);
      expect(re.hasMatch('  assets/** filter=lfs'), isTrue);
    });
    test('ignores the filter mentioned only in a comment', () {
      expect(re.hasMatch('# remember to set filter=lfs later'), isFalse);
      expect(re.hasMatch('*.txt text # not filter=lfs'), isFalse);
    });
  });

  group('lfsUntrackTarget', () {
    test('root, nested and deeper sources', () {
      expect(lfsUntrackTarget('*.psd', '.gitattributes'), (
        dir: '',
        pattern: '*.psd',
      ));
      expect(lfsUntrackTarget('sub/*.psd', 'sub/.gitattributes'), (
        dir: 'sub',
        pattern: '*.psd',
      ));
      expect(lfsUntrackTarget('a/b/*.psd', 'a/b/.gitattributes'), (
        dir: 'a/b',
        pattern: '*.psd',
      ));
    });
    test('a source written with backslashes, as Windows lists it', () {
      expect(lfsUntrackTarget(r'sub/*.psd', r'sub\.gitattributes'), (
        dir: 'sub',
        pattern: '*.psd',
      ));
      expect(lfsUntrackTarget(r'a/b/*.psd', r'a\b\.gitattributes'), (
        dir: 'a/b',
        pattern: '*.psd',
      ));
    });
    test('backslashes in the pattern itself are escapes and are kept', () {
      expect(
        lfsUntrackTarget(r'x[[:space:]]\[1\].z', '.gitattributes').pattern,
        r'x[[:space:]]\[1\].z',
      );
    });
  });

  group('withoutLfsPattern', () {
    const escaped = r'x[[:space:]]\[1\].z';
    test('drops the LFS line for exactly that pattern', () {
      expect(
        withoutLfsPattern(
          '*.txt text\n$escaped filter=lfs diff=lfs merge=lfs -text\n',
          escaped,
        ),
        '*.txt text\n',
      );
    });
    test('keeps CRLF endings on the lines it leaves', () {
      expect(
        withoutLfsPattern(
          '*.txt text\r\n$escaped filter=lfs diff=lfs merge=lfs -text\r\n',
          escaped,
        ),
        '*.txt text\r\n',
      );
    });
    test('leaves a line for the same pattern without the LFS filter', () {
      expect(withoutLfsPattern('*.psd -text\n', '*.psd'), isNull);
    });
    test('does not match a longer pattern that starts the same', () {
      expect(
        withoutLfsPattern(
          '*.psdx filter=lfs diff=lfs merge=lfs -text\n',
          '*.psd',
        ),
        isNull,
      );
    });
    test('null when the pattern is not there', () {
      expect(withoutLfsPattern('', '*.psd'), isNull);
    });
  });

  group('revisionArgs', () {
    test('marks the end of options on git 2.24 and later', () {
      expect(revisionArgs('abc', 'git version 2.24.0'), [
        '--end-of-options',
        'abc',
      ]);
      expect(revisionArgs('-Osh', 'git version 2.55.0'), [
        '--end-of-options',
        '-Osh',
      ]);
    });
    test('passes a plain revision bare on older git', () {
      expect(revisionArgs('abc', 'git version 2.23.4'), ['abc']);
      expect(revisionArgs('abc^', 'garbage'), ['abc^']);
    });
    test('refuses an option-shaped revision it cannot guard', () {
      expect(revisionArgs('-Osh', 'git version 2.23.4'), isNull);
      expect(revisionArgs('--output=x', 'garbage'), isNull);
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

  test('parseCatFileBatch splits records by header, not byte size', () {
    const body1 = 'hello\n';
    const body2 = 'wörld'; // 6 bytes in UTF-8
    const raw =
        'aaaa blob 6\n$body1\n'
        'bbbb blob 6\n$body2\n';
    expect(parseCatFileBatch(raw, ['aaaa', 'bbbb']), {
      'aaaa': body1,
      'bbbb': body2,
    });
  });

  test('parseCatFileBatch is not misled by a byte count a malformed byte '
      'changed the length of', () {
    // GitService decodes stdout with allowMalformed: true, so a byte that
    // is not valid UTF-8 becomes U+FFFD — a different number of code units
    // than the byte it replaced. A header's declared size can no longer
    // line up with the decoded string, so it must not be used to find
    // where a record ends.
    const pointer =
        'version https://git-lfs.github.com/spec/v1\n'
        'oid sha256:'
        '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393\n'
        'size 9\n';
    final raw = 'aaaa blob 6\n�bc\nbbbb blob ${pointer.length}\n$pointer\n';
    expect(parseCatFileBatch(raw, ['aaaa', 'bbbb']), {
      'aaaa': '�bc',
      'bbbb': pointer,
    });
  });

  test(
    'parseCatFileBatch stops once the next expected header is not found',
    () {
      const raw = 'aaaa blob 3\nabc\nbbbb blob 4\nabcd\n';
      // 'cccc' was requested too, but the answer was truncated before it, so
      // 'bbbb' cannot be bounded and is dropped along with anything after.
      expect(parseCatFileBatch(raw, ['aaaa', 'bbbb', 'cccc']), {'aaaa': 'abc'});
    },
  );

  group('parseLfsLsFiles', () {
    const a =
        '482b8673d879f129dbcc30eb80fcf939481fd963bba4e0a7ebcc2df0e9f50c7b';
    const b =
        'c37454b5337b1482c5a42b733bf5fff3f9a28714f9f1547512d8db046112bd92';
    test('reads checked-out and pointer entries', () {
      expect(parseLfsLsFiles('$a * a.bin\n$b - b c.bin\n'), const [
        LfsLsEntry(oid: a, path: 'a.bin', checkedOut: true),
        LfsLsEntry(oid: b, path: 'b c.bin', checkedOut: false),
      ]);
    });
    test('skips lines it does not recognise', () {
      expect(
        parseLfsLsFiles('\nwarning: x\n$a ? a.bin\nshort - a.bin\n'),
        isEmpty,
      );
    });
    test('tolerates CRLF line endings', () {
      expect(parseLfsLsFiles('$a * a.bin\r\n$b - c.bin\r\n'), const [
        LfsLsEntry(oid: a, path: 'a.bin', checkedOut: true),
        LfsLsEntry(oid: b, path: 'c.bin', checkedOut: false),
      ]);
    });
  });

  group('parseLfsPruneDryRun', () {
    test('nothing to prune', () {
      expect(
        parseLfsPruneDryRun('2 local objects, 2 retained, done.\n'),
        const LfsPrunePreview(count: 0),
      );
    });
    test('counts from the summary numbers, not the detail lines', () {
      // git-lfs prints at most one ` * <oid> (<size>)` detail line no matter
      // how many objects it actually prunes, so the count must come from the
      // summary's `local − retained` difference, not from counting these
      // lines: here that would undercount 2 as 1.
      const oid =
          '482b8673d879f129dbcc30eb80fcf939481fd963bba4e0a7ebcc2df0e9f50c7b';
      expect(
        parseLfsPruneDryRun(
          '3 local objects, 1 retained, done.\n'
          ' * $oid (3.0 KB), done.\n',
        ),
        const LfsPrunePreview(count: 2),
      );
    });
    test('the captured single-object real output parses', () {
      // Captured from git-lfs 3.8.0 on darwin arm64: one file pushed then
      // removed in a follow-up commit, then `git lfs prune --dry-run
      // --verbose` after pushing both commits to origin.
      const pruneSome =
          '1 local object, 0 retained, done.\n'
          '\n'
          ' * f4b619328582b9679ce61f8cb487e47daf46583327771dc85e5931f504b95231 '
          '(4.0 KB), done.\n';
      expect(parseLfsPruneDryRun(pruneSome), const LfsPrunePreview(count: 1));
    });
    test('the captured four-object real output parses', () {
      // Also reproduced on git-lfs 3.8: pruning 4 objects of different
      // sizes still prints only a single detail line, so the summary is the
      // only reliable source for the count.
      const pruneFour =
          '4 local objects, 0 retained, done.\n'
          ' * 1fb01e2582b7379118128c319fd04b565e6eff947b8dda317bceda9363e7385a '
          '(20 KB), done.\n';
      expect(parseLfsPruneDryRun(pruneFour), const LfsPrunePreview(count: 4));
    });
    test('tolerates CRLF line endings', () {
      const pruneFourCrlf =
          '4 local objects, 0 retained, done.\r\n'
          ' * 1fb01e2582b7379118128c319fd04b565e6eff947b8dda317bceda9363e7385a '
          '(20 KB), done.\r\n';
      expect(
        parseLfsPruneDryRun(pruneFourCrlf),
        const LfsPrunePreview(count: 4),
      );
    });
    test('more retained than local never goes below zero', () {
      expect(
        parseLfsPruneDryRun('2 local objects, 5 retained, done.\n'),
        const LfsPrunePreview(count: 0),
      );
    });
    test('unrecognisable output is null, not zero', () {
      expect(parseLfsPruneDryRun(''), isNull);
      expect(parseLfsPruneDryRun('fatal: not a git repository\n'), isNull);
    });
  });

  group('parseLfsTrackList with lockable patterns', () {
    test('the [lockable] tag is not part of the pattern', () {
      final list = parseLfsTrackList(
        'Listing tracked patterns\n'
        '    *.psd [lockable] (.gitattributes)\n'
        '    *.bin (.gitattributes)\n'
        'Listing excluded patterns\n',
      );
      expect(list.map((t) => t.pattern), ['*.psd', '*.bin']);
      expect(list.map((t) => t.lockable), [true, false]);
      expect(list.first.source, '.gitattributes');
    });
    test('equality still keys on pattern and source', () {
      expect(
        const LfsTrackedPattern(
          pattern: '*.psd',
          source: '.gitattributes',
          lockable: true,
        ),
        const LfsTrackedPattern(pattern: '*.psd', source: '.gitattributes'),
      );
    });
  });

  group('parseLfsTrackList', () {
    test('tracked patterns with their source file', () {
      expect(
        parseLfsTrackList(
          'Listing tracked patterns\n'
          '    *.psd (.gitattributes)\n'
          '    sub/odd[[:space:]]\\[1\\].bin (sub/.gitattributes)\n'
          'Listing excluded patterns\n'
          '    *.tmp (.gitattributes)\n',
        ),
        const [
          LfsTrackedPattern(pattern: '*.psd', source: '.gitattributes'),
          LfsTrackedPattern(
            pattern: r'sub/odd[[:space:]]\[1\].bin',
            source: 'sub/.gitattributes',
          ),
        ],
      );
    });
    test('tolerates CRLF line endings', () {
      expect(
        parseLfsTrackList(
          'Listing tracked patterns\r\n'
          '    *.psd (.gitattributes)\r\n'
          'Listing excluded patterns\r\n',
        ),
        const [LfsTrackedPattern(pattern: '*.psd', source: '.gitattributes')],
      );
    });
    test('none', () {
      expect(
        parseLfsTrackList(
          'Listing tracked patterns\nListing excluded patterns\n',
        ),
        isEmpty,
      );
    });
  });

  test('isLfsPrePushHook', () {
    expect(isLfsPrePushHook('#!/bin/sh\ngit lfs pre-push "\$@"\n'), isTrue);
    expect(isLfsPrePushHook('#!/bin/sh\ngit-lfs pre-push "\$@"\n'), isTrue);
    expect(isLfsPrePushHook('#!/bin/sh\necho mine\n'), isFalse);
    expect(isLfsPrePushHook(''), isFalse);
  });

  group('lfsIncludeSafe', () {
    for (final ok in ['art.psd', 'dir/b c.bin', 'ünï.psd', '-dash.bin']) {
      test('safe: $ok', () => expect(lfsIncludeSafe(ok), isTrue));
    }
    for (final bad in [
      'a,b.psd',
      'x*.psd',
      'x?.psd',
      'x[1].psd',
      r'x\y',
      'x]',
    ]) {
      test('unsafe: $bad', () => expect(lfsIncludeSafe(bad), isFalse));
    }
  });

  group('lfsExtensionPattern', () {
    test('by extension', () {
      expect(lfsExtensionPattern('art/cover.PSD'), '*.PSD');
      expect(lfsExtensionPattern('a.tar.gz'), '*.gz');
      // A dotfile with a further dot has a real extension after it.
      expect(lfsExtensionPattern('.env.local'), '*.local');
    });
    test('none when there is no usable extension', () {
      expect(lfsExtensionPattern('Makefile'), isNull);
      expect(lfsExtensionPattern('.gitignore'), isNull);
      expect(lfsExtensionPattern('dir.d/file'), isNull);
      expect(lfsExtensionPattern('a.b[1]'), isNull);
      expect(lfsExtensionPattern('a.b c'), isNull);
      expect(lfsExtensionPattern('archive.'), isNull);
    });
  });

  const lockJson =
      '{"id":"123","path":"art/a.psd","owner":{"name":"Ann"},'
      '"locked_at":"2026-09-30T10:00:00Z"}';
  final lockA = LfsLock(
    id: '123',
    path: 'art/a.psd',
    owner: 'Ann',
    lockedAt: DateTime.utc(2026, 9, 30, 10),
  );

  group('parseLfsLocksJson', () {
    test('empty array', () => expect(parseLfsLocksJson('[]'), isEmpty));
    test('numeric id kept as its string form', () {
      final locks = parseLfsLocksJson(
        '[{"id":42,"path":"a.psd","owner":{"name":"A"},'
        '"locked_at":"2026-09-30T10:00:00Z"}]',
      )!;
      expect(locks.single.id, '42');
    });
    test('one lock', () {
      final locks = parseLfsLocksJson('[$lockJson]')!;
      expect(locks, [lockA]);
      expect(locks.single.lockedAt!.isUtc, isTrue);
    });
    test('two locks keep order', () {
      const b = '{"id":"9","path":"b.bin","owner":{"name":"Bo"}}';
      final locks = parseLfsLocksJson('[$lockJson,$b]')!;
      expect(locks.map((l) => l.id), ['123', '9']);
    });
    test('missing owner and locked_at', () {
      final l = parseLfsLocksJson('[{"id":"1","path":"a"}]')!.single;
      expect(l.owner, '');
      expect(l.lockedAt, isNull);
    });
    test('wrong-typed elements are skipped', () {
      final locks = parseLfsLocksJson('[1,{"id":true,"path":"a"},$lockJson]')!;
      expect(locks, [lockA]);
    });
    test('not an array or not JSON is null', () {
      expect(parseLfsLocksJson('nope'), isNull);
      expect(parseLfsLocksJson('{}'), isNull);
      expect(parseLfsLocksJson(''), isNull);
    });
  });

  group('parseLfsLocksVerifyJson', () {
    test('both empty', () {
      final r = parseLfsLocksVerifyJson('{"ours":[],"theirs":[]}')!;
      expect(r.ours, isEmpty);
      expect(r.theirs, isEmpty);
    });
    test('splits ours and theirs', () {
      final r = parseLfsLocksVerifyJson(
        '{"ours":[$lockJson],"theirs":[{"id":"2","path":"t","owner":{"name":"Tim"}}]}',
      )!;
      expect(r.ours, [lockA]);
      expect(r.theirs.single.owner, 'Tim');
    });
    test('missing key is empty', () {
      final r = parseLfsLocksVerifyJson('{"ours":[$lockJson]}')!;
      expect(r.ours, [lockA]);
      expect(r.theirs, isEmpty);
    });
    test('not JSON is null', () {
      expect(parseLfsLocksVerifyJson('nope'), isNull);
      expect(parseLfsLocksVerifyJson('[]'), isNull);
    });
  });

  group('parseLfsLockResultJson', () {
    test('object gives a lock', () {
      expect(parseLfsLockResultJson(lockJson), lockA);
    });
    test('array or not JSON is null', () {
      expect(parseLfsLockResultJson('[]'), isNull);
      expect(parseLfsLockResultJson('nope'), isNull);
    });
  });

  group('parseLfsUnlockFailure', () {
    test('returns the first reason', () {
      expect(
        parseLfsUnlockFailure(
          '[{"id":"7","unlocked":false,"reason":"Unable to unlock 7: no"}]',
        ),
        'Unable to unlock 7: no',
      );
    });
    test('entries keyed by path', () {
      expect(
        parseLfsUnlockFailure(
          '[{"path":"a.psd","unlocked":false,"reason":"unable get lock ID"}]',
        ),
        'unable get lock ID',
      );
    });
    test('a single object is read like a one-entry list', () {
      expect(parseLfsUnlockFailure('{"id":"7","unlocked":true}'), isNull);
      expect(
        parseLfsUnlockFailure('{"id":"7","unlocked":false,"reason":"no"}'),
        'no',
      );
    });
    test('all unlocked is null', () {
      expect(parseLfsUnlockFailure('[{"id":"7","unlocked":true}]'), isNull);
    });
    test('not JSON', () {
      expect(parseLfsUnlockFailure('boom'), 'unlock failed');
    });
  });

  group('lfsLocksUnsupported', () {
    for (final stderr in [
      'Locking a.psd failed: missing protocol: "file:///x/remote.git"',
      'Remote "origin" does not support the Git LFS locking API.',
      'Locking is not supported by this server',
      'Unable to list locks: https://host/x.git/info/lfs/locks [404] Not Found',
      'list locks: status 404',
      'HTTP 404 NOT FOUND',
    ]) {
      test('true: $stderr', () {
        expect(lfsLocksUnsupported(stderr), isTrue);
      });
    }
    for (final stderr in [
      'dial tcp 10.0.4.04:4040: connect: connection refused',
      'Locking a.psd failed: Post "https://h:4040/x.git/info/lfs/locks": '
          'dial tcp: lookup h: no such host',
      "Authentication failed for 'https://host/x.git/info/lfs/locks'",
      'Not Found',
      'object 4040404 not found',
    ]) {
      test('false: $stderr', () {
        expect(lfsLocksUnsupported(stderr), isFalse);
      });
    }
  });
}
