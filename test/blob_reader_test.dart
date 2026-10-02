import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// Integration tests: a real repository built with the system `git`, read back
/// as raw bytes.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  // Every byte value, so any text decoding on the way would show.
  final allBytes = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  BlobReader reader({int maxBytes = blobPreviewMaxBytes}) =>
      BlobReader(git: svc, bytes: svc, repoPath: dir.path, maxBytes: maxBytes);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_blob_');
    await g(['init', '-q']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.bin').writeAsBytes(allBytes);
    await g(['add', 'a.bin']);
    await g(['commit', '-q', '-m', 'A']);
  });

  tearDown(() => dir.delete(recursive: true));

  test('runBytes returns stdout byte for byte', () async {
    final out = await svc.runBytes(
      ['cat-file', 'blob', 'HEAD:a.bin'],
      repoPath: dir.path,
      maxBytes: 1 << 20,
    );
    expect(out, allBytes);
  });

  test('runBytes gives up once output passes the cap', () async {
    final out = await svc.runBytes(
      ['cat-file', 'blob', 'HEAD:a.bin'],
      repoPath: dir.path,
      maxBytes: 100,
    );
    expect(out, isNull);
  });

  test('runBytes is null when git fails', () async {
    final out = await svc.runBytes(
      ['cat-file', 'blob', 'HEAD:missing'],
      repoPath: dir.path,
      maxBytes: 1 << 20,
    );
    expect(out, isNull);
  });

  test('reads a revision blob without altering a single byte', () async {
    final load = await reader().read(const RevisionBlob('HEAD', 'a.bin'));
    expect(load!.size, 256);
    expect(load.bytes, allBytes);
  });

  test('reads the index copy and the file on disk', () async {
    await File('${dir.path}/a.bin').writeAsBytes([1, 2, 3]);
    final index = await reader().read(const IndexBlob('a.bin'));
    expect(index!.bytes, allBytes);
    final disk = await reader().read(const WorktreeBlob('a.bin'));
    expect(disk!.bytes, [1, 2, 3]);
    expect(disk.size, 3);
  });

  test('a blob over the cap reports its size and is not read', () async {
    final load = await reader(maxBytes: 100)
        .read(const RevisionBlob('HEAD', 'a.bin'));
    expect(load!.size, 256);
    expect(load.tooLarge, isTrue);
    expect(load.bytes, isNull);

    final disk = await reader(maxBytes: 100).read(const WorktreeBlob('a.bin'));
    expect(disk!.tooLarge, isTrue);
    expect(disk.size, 256);
  });

  test('a side that does not exist is null', () async {
    expect(await reader().read(const RevisionBlob('HEAD', 'nope')), isNull);
    expect(await reader().read(const IndexBlob('a.bin', stage: 2)), isNull);
    expect(await reader().read(const WorktreeBlob('nope')), isNull);
  });

  test('a revision git would read as an option is never run', () async {
    expect(await reader().read(const RevisionBlob('-p', 'a.bin')), isNull);
  });

  test('a worktree path that leaves the repository is refused', () async {
    final outside = await Directory.systemTemp.createTemp('mergelio_out_');
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/secret').writeAsBytes([9]);
    expect(await reader().read(const WorktreeBlob('../secret')), isNull);
    expect(await reader().read(WorktreeBlob('${outside.path}/secret')), isNull);
    await Link('${dir.path}/link').create('${outside.path}/secret');
    expect(await reader().read(const WorktreeBlob('link')), isNull);
  });

  group('runBytes failures say what went wrong', () {
    test('a repository directory that is gone is not blamed on git', () async {
      await expectLater(
        svc.runBytes(
          ['cat-file', 'blob', 'HEAD:a.bin'],
          repoPath: '${dir.path}/gone',
          maxBytes: 100,
        ),
        throwsA(
          isA<GitException>().having(
            (e) => e is GitUnavailableException,
            'blames git',
            isFalse,
          ),
        ),
      );
    });

    test(
      'a broken toolchain is reported, not taken for a missing blob',
      () async {
        const shim = SystemGitService(gitBinary: '/bin/sh');
        await expectLater(
          shim.runBytes([
            '-c',
            r'echo "xcrun: error: invalid active developer path" >&2; exit 1',
          ], maxBytes: 100),
          throwsA(isA<GitUnavailableException>()),
        );
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );
  });
}
