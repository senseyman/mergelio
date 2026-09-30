import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mt_measure');
    addTearDown(() => dir.delete(recursive: true));
  });

  Future<void> write(String rel, int bytes) async {
    final f = File(p.join(dir.path, rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List.filled(bytes, 0));
  }

  test('splits packs, loose objects, LFS objects and the rest', () async {
    await write('objects/pack/pack-1.pack', 100);
    await write('objects/pack/pack-1.idx', 10);
    await write('objects/ab/cdef', 7);
    await write('objects/12/3456', 3);
    await write('objects/info/packs', 2);
    await write('lfs/objects/aa/bb/aabb', 50);
    await write('refs/heads/main', 41);
    await write('HEAD', 21);

    final s = await measureGitDir(dir.path);
    expect(s.packBytes, 110);
    expect(s.looseBytes, 10);
    expect(s.lfsBytes, 50);
    expect(s.otherBytes, 2 + 41 + 21);
    expect(s.totalBytes, 110 + 10 + 50 + 64);
  });

  test('missing directories count as zero', () async {
    final s = await measureGitDir(p.join(dir.path, 'nope'));
    expect(s.totalBytes, 0);
  });

  test('the off-thread wrapper answers the same', () async {
    await write('objects/pack/x.pack', 5);
    final s = await measureGitDirOffThread(dir.path);
    expect(s.packBytes, 5);
  });
}
