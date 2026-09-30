import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/maintenance.dart';

void main() {
  group('parseCountObjects', () {
    test('reads -v output, KiB sizes as bytes', () {
      final c = parseCountObjects(
        'count: 3\nsize: 12\nin-pack: 40\npacks: 2\nsize-pack: 2048\n'
        'prune-packable: 1\ngarbage: 4\nsize-garbage: 8\n',
      );
      expect(c.looseCount, 3);
      expect(c.looseBytes, 12 * 1024);
      expect(c.packedCount, 40);
      expect(c.packCount, 2);
      expect(c.packBytes, 2048 * 1024);
      expect(c.prunePackable, 1);
      expect(c.garbageCount, 4);
      expect(c.garbageBytes, 8 * 1024);
    });

    test('missing or unreadable keys are zero', () {
      final c = parseCountObjects('count: x\nnoise\n');
      expect(c.looseCount, 0);
      expect(c.packBytes, 0);
    });
  });

  group('parseBlobBatch / topBlobs', () {
    const batch =
        'commit e2822a0e18f3703238928eea709b705282a43051 208 \n'
        'tree 718ba0fe7b3d70ccfb24ff59840e44c2cfd8b0c6 70 \n'
        'blob ce013625030ba8dba906f756967f9e9ca394464a 6 a b.txt\n'
        'blob 3553ce4cfe647ba6daa9472f3c792b7985b5e8b2 5000 big.bin\n'
        'blob 3553ce4cfe647ba6daa9472f3c792b7985b5e8b2 5000 copy/big.bin\n'
        'blob 1111111111111111111111111111111111111111 900 \n'
        'tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904 0 \n';

    test('keeps blobs only, first path per sha, spaces in paths', () {
      final blobs = parseBlobBatch(batch);
      expect(blobs.map((b) => b.path), ['a b.txt', 'big.bin', '']);
      expect(blobs[1].size, 5000);
      expect(blobs[1].sha, '3553ce4cfe647ba6daa9472f3c792b7985b5e8b2');
    });

    test('topBlobs sorts by size and caps at n', () {
      final top = topBlobs(batch, 2);
      expect(top.map((b) => b.size), [5000, 900]);
    });

    test('ties order by path so the list is stable', () {
      final top = topBlobs('blob ${'a' * 40} 10 z\nblob ${'b' * 40} 10 a\n', 5);
      expect(top.map((b) => b.path), ['a', 'z']);
    });

    test('malformed lines are skipped', () {
      expect(parseBlobBatch('blob abc\nblob ${'c' * 40} nope p\n'), isEmpty);
    });
  });

  test('parseIntroducingCommit reads the first line', () {
    final c = parseIntroducingCommit(
      'e2822a0\x1fe2822a0\x1f2026-09-30T22:16:18+01:00\x1fadd files\n'
      'ffff\x1fffff\x1f2026-10-01T00:00:00+01:00\x1fremove\n',
    );
    expect(c!.sha, 'e2822a0');
    expect(c.subject, 'add files');
    expect(c.date, '2026-09-30T22:16:18+01:00');
    expect(parseIntroducingCommit(''), isNull);
    expect(parseIntroducingCommit('only\x1ftwo'), isNull);
  });

  test('countReflogExpiry counts would-prune lines only', () {
    expect(
      countReflogExpiry(
        'would prune commit: a\nkeep commit: b\nwould prune checkout: x\n',
      ),
      2,
    );
    expect(countReflogExpiry(''), 0);
  });

  group('pickTrunk', () {
    test("prefers origin/HEAD's branch when it exists locally", () {
      expect(
        pickTrunk(
          branches: {'dev', 'main', 'trunk'},
          originHead: 'origin/trunk',
          current: 'dev',
        ),
        'trunk',
      );
    });

    test('falls back to main, then master, then the current branch', () {
      expect(
        pickTrunk(
          branches: {'main', 'master'},
          originHead: 'origin/gone',
          current: 'x',
        ),
        'main',
      );
      expect(
        pickTrunk(branches: {'master', 'x'}, originHead: null, current: 'x'),
        'master',
      );
      expect(pickTrunk(branches: {'x'}, originHead: null, current: 'x'), 'x');
      expect(pickTrunk(branches: {}, originHead: null, current: null), isNull);
    });
  });

  group('branch hygiene', () {
    final now = DateTime.utc(2026, 9, 30);
    int ago(int days) =>
        now.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

    test('parseBranchInfo reads name, date and gone upstream', () {
      final infos = parseBranchInfo(
        'main\t${ago(1)}\t\n'
        'old\t${ago(200)}\t[ahead 1]\n'
        'feat/x\t${ago(2)}\t[gone]\n',
      );
      expect(infos.map((i) => i.name), ['main', 'old', 'feat/x']);
      expect(infos[1].lastCommit, now.subtract(const Duration(days: 200)));
      expect(infos[2].gone, isTrue);
      expect(infos[1].gone, isFalse);
    });

    test('classifies merged and stale, skips trunk, current and fresh', () {
      final infos = parseBranchInfo(
        'main\t${ago(300)}\t\n'
        'cur\t${ago(300)}\t\n'
        'done\t${ago(1)}\t\n'
        'old\t${ago(91)}\t\n'
        'fresh\t${ago(89)}\t\n'
        'gone\t${ago(1)}\t[gone]\n'
        'held\t${ago(1)}\t\n',
      );
      final out = classifyBranches(
        infos: infos,
        merged: {'main', 'cur', 'done', 'held'},
        trunk: 'main',
        current: 'cur',
        heldBy: {'held': '/wt/held'},
        now: now,
      );
      expect(out.map((b) => b.name), ['done', 'held', 'gone', 'old']);
      final done = out.first;
      expect(done.merged, isTrue);
      expect(done.needsForce, isFalse);
      expect(done.selectable, isTrue);
      final held = out[1];
      expect(held.selectable, isFalse);
      expect(held.heldBy, '/wt/held');
      final gone = out[2];
      expect(gone.gone, isTrue);
      expect(gone.needsForce, isTrue);
      expect(out[3].merged, isFalse);
    });
  });

  test('refsFingerprint is stable and order-sensitive to content', () {
    final a = refsFingerprint('x refs/heads/main\n');
    expect(a, refsFingerprint('x refs/heads/main\n'));
    expect(a, isNot(refsFingerprint('y refs/heads/main\n')));
    expect(a, hasLength(40));
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(6 * 1024 * 1024 * 1024), '6.0 GB');
  });

  test('BlobScan survives a JSON round-trip', () {
    final scan = BlobScan(
      scannedAt: '2026-09-30T10:00:00.000Z',
      fingerprint: 'f' * 40,
      blobs: [
        const BigBlob(
          BlobEntry(sha: 'aa', size: 10, path: 'p q'),
          IntroducingCommit(
            sha: 'c1',
            shortSha: 'c',
            date: '2026-01-01T00:00:00Z',
            subject: 's',
          ),
        ),
        const BigBlob(BlobEntry(sha: 'bb', size: 5, path: ''), null),
      ],
    );
    final back = BlobScan.fromJson(scan.toJson());
    expect(back.scannedAt, scan.scannedAt);
    expect(back.fingerprint, scan.fingerprint);
    expect(back.blobs.first.blob.path, 'p q');
    expect(back.blobs.first.commit!.subject, 's');
    expect(back.blobs.last.commit, isNull);
    expect(back.blobs.last.blob.size, 5);
  });
}
