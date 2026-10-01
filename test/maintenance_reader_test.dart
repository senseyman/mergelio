import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/maintenance.dart';

/// Scripts git by exact argument list and records calls, timeouts, stdin and
/// the cancel handle each one got.
class _FakeGit implements GitService {
  final calls = <List<String>>[];
  final responses = <String, GitResult>{};
  final timeouts = <String, Duration?>{};
  final stdins = <String, String?>{};
  final cancels = <String, GitCancel?>{};

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    final key = args.join(' ');
    timeouts[key] = timeout;
    stdins[key] = stdin;
    cancels[key] = cancel;
    if (cancel?.isCancelled ?? false) {
      throw GitCancelledException('git $key cancelled');
    }
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _FakeGit git;
  late MaintenanceReader reader;

  setUp(() {
    git = _FakeGit();
    reader = MaintenanceReader(git, '/repo');
  });

  group('commonGitDir', () {
    test('resolves a relative answer against the repository', () async {
      git.responses['rev-parse --git-common-dir'] = const GitResult(
        0,
        '.git\n',
        '',
      );
      expect(await reader.commonGitDir(), '/repo/.git');
    });

    test('keeps an absolute answer', () async {
      git.responses['rev-parse --git-common-dir'] = const GitResult(
        0,
        '/main/.git\n',
        '',
      );
      expect(await reader.commonGitDir(), '/main/.git');
    });

    test('throws when git fails', () async {
      git.responses['rev-parse --git-common-dir'] = const GitResult(
        128,
        '',
        'no',
      );
      expect(reader.commonGitDir(), throwsA(isA<GitException>()));
    });
  });

  test('countObjects reads count-objects -v', () async {
    git.responses['count-objects -v'] = const GitResult(0, 'count: 4\n', '');
    expect((await reader.countObjects()).looseCount, 4);
  });

  test('reflogExpiryCount runs the dry run with configured expiry', () async {
    git.responses['reflog expire --all --dry-run --verbose'] = const GitResult(
      0,
      'would prune a\nwould prune b\n',
      '',
    );
    expect(await reader.reflogExpiryCount(), 2);
    // It walks every reflog of every ref, which can outrun the default.
    expect(
      git.timeouts['reflog expire --all --dry-run --verbose'],
      MaintenanceReader.slowReadTimeout,
    );
  });

  group('branchHygiene', () {
    final now = DateTime.utc(2026, 9, 30);
    final old = now.subtract(const Duration(days: 200));
    int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

    setUp(() {
      git.responses['for-each-ref --format=$branchInfoFormat refs/heads'] =
          GitResult(
            0,
            'trunk\t${secs(old)}\t\n'
                'done\t${secs(now)}\t\n'
                'old\t${secs(old)}\t\n',
            '',
          );
      git.responses['symbolic-ref --quiet --short refs/remotes/origin/HEAD'] =
          const GitResult(0, 'origin/trunk\n', '');
      git.responses['branch --show-current'] = const GitResult(0, 'done\n', '');
      git.responses['for-each-ref --merged=trunk --format=%(refname:short) '
          'refs/heads'] = const GitResult(
        0,
        'trunk\ndone\n',
        '',
      );
    });

    test('measures against the remote default and skips current', () async {
      final h = await reader.branchHygiene(now: now, heldBy: const {});
      expect(h.trunk, 'trunk');
      expect(h.branches.map((b) => b.name), ['old']);
      expect(h.branches.single.needsForce, isTrue);
    });

    test('without origin/HEAD falls back and still answers', () async {
      git.responses['symbolic-ref --quiet --short refs/remotes/origin/HEAD'] =
          const GitResult(1, '', '');
      git.responses['branch --show-current'] = const GitResult(0, 'x\n', '');
      final h = await reader.branchHygiene(
        now: now,
        heldBy: const {'done': '/wt'},
      );
      // No main/master either, so the current branch is the trunk; nothing
      // merged into `x` was scripted.
      expect(h.trunk, 'x');
      expect(h.branches.map((b) => b.name), ['old', 'trunk']);
    });
  });

  test('refsFingerprint digests the ref listing', () async {
    git.responses['for-each-ref --format=%(objectname) %(refname)'] =
        const GitResult(0, 'a refs/heads/main\n', '');
    expect(
      await reader.currentRefsFingerprint(),
      refsFingerprint('a refs/heads/main\n'),
    );
  });

  group('scanBlobs', () {
    final shaA = 'a' * 40, shaB = 'b' * 40;
    const listKey =
        'cat-file --batch-all-objects --batch-check=$allObjectsFormat';
    String logKey(String sha) =>
        'log --all --reverse --format=$blobOriginFormat --name-only '
        '--find-object=$sha';

    setUp(() {
      git.responses['for-each-ref --format=%(objectname) %(refname)'] =
          const GitResult(0, 'x refs/heads/main\n', '');
      git.responses[listKey] = GitResult(
        0,
        'commit ${'c' * 40} 200\n'
            'blob $shaA 5000\n'
            'blob $shaB 6\n',
        '',
      );
      git.responses[logKey(shaA)] = const GitResult(
        0,
        'c1\x1fc\x1f2026-01-01T00:00:00Z\x1fadd big\n\nbig.bin\n',
        '',
      );
    });

    test(
      'lists every object once, then finds where the winners came from',
      () async {
        final scan = await reader.scanBlobs(
          top: 1,
          now: DateTime.utc(2026, 9, 30, 12),
        );
        // No object listing is piped through the app: git enumerates the
        // object store itself.
        expect(git.calls.where((c) => c.first == 'rev-list'), isEmpty);
        expect(git.stdins[listKey], isNull);
        expect(scan.blobs.single.blob.sha, shaA);
        expect(scan.blobs.single.blob.path, 'big.bin');
        expect(scan.blobs.single.commit!.subject, 'add big');
        // Only the winner is looked up.
        expect(git.calls.where((c) => c.first == 'log'), hasLength(1));
        expect(scan.fingerprint, refsFingerprint('x refs/heads/main\n'));
        expect(scan.scannedAt, '2026-09-30T12:00:00.000Z');
      },
    );

    test(
      'a blob no commit reaches keeps its size, without path or commit',
      () async {
        final scan = await reader.scanBlobs(top: 2, now: DateTime.utc(2026));
        final orphan = scan.blobs.last;
        expect(orphan.blob.sha, shaB);
        expect(orphan.blob.path, '');
        expect(orphan.commit, isNull);
      },
    );

    test('passes a long timeout and the cancel handle to every step', () async {
      final cancel = GitCancel();
      await reader.scanBlobs(top: 2, now: DateTime.utc(2026), cancel: cancel);
      for (final key in [listKey, logKey(shaA), logKey(shaB)]) {
        expect(git.timeouts[key], MaintenanceReader.scanTimeout, reason: key);
        expect(git.cancels[key], same(cancel), reason: key);
      }
    });

    test('a cancelled scan stops with GitCancelledException', () async {
      final cancel = GitCancel()..cancel();
      expect(
        reader.scanBlobs(top: 1, now: DateTime.utc(2026), cancel: cancel),
        throwsA(isA<GitCancelledException>()),
      );
    });

    test('a failed listing throws', () async {
      git.responses[listKey] = const GitResult(128, '', 'bad');
      expect(
        reader.scanBlobs(top: 1, now: DateTime.utc(2026)),
        throwsA(isA<GitException>()),
      );
    });
  });
}
