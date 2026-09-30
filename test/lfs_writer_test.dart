import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:path/path.dart' as p;

class _Capture implements GitService {
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
  final envs = <Map<String, String>?>[];
  final dirs = <String?>[];

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
    timeouts.add(timeout);
    envs.add(environment);
    dirs.add(repoPath);
    return const GitResult(0, 'out', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _Capture git;
  late GitWriter w;

  setUp(() {
    git = _Capture();
    w = GitWriter(git, '/r');
  });

  // Transfers are the git-lfs commands that talk to a server.
  List<String> last() => git.calls.last;

  test('pull', () async {
    await w.lfsPull();
    expect(last(), ['lfs', 'pull']);

    await w.lfsPull(include: 'b c.bin');
    expect(last(), ['lfs', 'pull', '--include=b c.bin']);
  });

  test('fetch all and fetch one object', () async {
    await w.lfsFetchAll();
    expect(last(), ['lfs', 'fetch', '--all']);

    await w.lfsFetchObject('origin', 'abc^', 'art.psd');
    expect(last(), ['lfs', 'fetch', 'origin', 'abc^', '--include=art.psd']);
  });

  test('prune preview and prune', () async {
    final r = await w.lfsPruneDryRun();
    expect(r.stdout, 'out');
    expect(last(), ['lfs', 'prune', '--dry-run', '--verbose']);

    await w.lfsPrune();
    expect(last(), ['lfs', 'prune']);
  });

  test(
    'transfers use the transfer timeout and the network environment',
    () async {
      await w.lfsPull();
      await w.lfsFetchAll();
      await w.lfsFetchObject('origin', 'abc', 'art.psd');
      await w.lfsPruneDryRun();
      await w.lfsPrune();

      // _netEnv() itself runs a `git config` once per writer, so filter down
      // to the lfs transfer calls before checking their timeout/environment.
      for (var i = 0; i < git.calls.length; i++) {
        if (git.calls[i].first != 'lfs') continue;
        expect(git.timeouts[i], GitWriter.lfsTransferTimeout);
        expect(git.envs[i], isNotNull);
      }
    },
  );

  test('track, untrack, list, install --local', () async {
    await w.lfsTrack('*.psd');
    expect(last(), ['lfs', 'track', '--', '*.psd']);

    await w.lfsTrackFile('sub/odd [1].bin');
    expect(last(), ['lfs', 'track', '--filename', '--', 'sub/odd [1].bin']);

    await w.lfsUntrack('*.psd');
    expect(last(), ['lfs', 'untrack', '--', '*.psd']);

    final out = await w.lfsTrackList();
    expect(out, 'out');
    expect(last(), ['lfs', 'track']);

    await w.lfsInstallLocal();
    expect(last(), ['lfs', 'install', '--local']);
  });

  test('local git-lfs commands use the local timeout', () async {
    await w.lfsTrack('*.psd');
    await w.lfsTrackFile('a.psd');
    await w.lfsUntrack('*.psd');
    await w.lfsTrackList();
    await w.lfsInstallLocal();

    expect(git.calls, hasLength(5));
    expect(git.timeouts, everyElement(GitWriter.lfsLocalTimeout));
    expect(GitWriter.lfsLocalTimeout, const Duration(seconds: 60));
  });

  test('untrack runs in the subdirectory the pattern belongs to', () async {
    await w.lfsUntrack('*.psd');
    expect(git.dirs.last, '/r');

    await w.lfsUntrack('*.psd', dir: 'sub/deeper');
    expect(last(), ['lfs', 'untrack', '--', '*.psd']);
    expect(git.dirs.last, p.join('/r', 'sub/deeper'));
    expect(git.timeouts.last, GitWriter.lfsLocalTimeout);
  });

  test('stageGitattributes adds only the listed changed files', () async {
    await w.stageGitattributes();
    // The capture fake answers every listing with 'out'.
    expect(git.calls, [
      [
        'ls-files',
        '-z',
        '-m',
        '-o',
        '--exclude-standard',
        '--',
        ':(glob)**/.gitattributes',
      ],
      ['add', '--', 'out'],
    ]);
  });

  test('renormalize batches at 200 paths', () async {
    final paths = [for (var i = 0; i < 450; i++) 'f$i.psd'];
    await w.renormalize(paths);

    expect(git.calls, hasLength(3));
    for (final c in git.calls) {
      expect(c.take(3), ['add', '--renormalize', '--']);
    }
    final flattened = git.calls.expand((c) => c.skip(3)).toList();
    expect(flattened, paths);
    expect(git.timeouts, everyElement(GitWriter.lfsTransferTimeout));
  });

  test('failure throws GitException', () async {
    final failing = _Failing();
    final w2 = GitWriter(failing, '/r');
    await expectLater(w2.lfsPull(), throwsA(isA<GitException>()));
    await expectLater(w2.lfsTrack('*.psd'), throwsA(isA<GitException>()));
  });

  group('lfs locks', () {
    test('exact argv for list, lock and unlock', () async {
      await w.lfsLockList();
      expect(last(), ['lfs', 'locks', '--verify', '--json', '--limit', '1000']);

      final out = await w.lfsLock('-x.psd');
      expect(out, 'out');
      expect(last(), ['lfs', 'lock', '--json', '--', '-x.psd']);

      expect(await w.lfsUnlock('7'), 'out');
      expect(last(), ['lfs', 'unlock', '--json', '--id', '7']);

      await w.lfsUnlock('7', force: true);
      expect(last(), ['lfs', 'unlock', '--json', '--force', '--id', '7']);
    });

    test('lock commands use the local timeout and network env', () async {
      await w.lfsLockList();
      await w.lfsLock('a.psd');
      await w.lfsUnlock('7');
      for (var i = 0; i < git.calls.length; i++) {
        if (git.calls[i].first != 'lfs') continue;
        expect(git.timeouts[i], GitWriter.lfsLocalTimeout);
        expect(git.envs[i], isNotNull);
      }
      expect(git.calls.where((c) => c.first == 'lfs'), hasLength(3));
    });

    test(
      'unlock refuses an empty or dash-leading id, records no call',
      () async {
        await expectLater(w.lfsUnlock('-7'), throwsA(isA<ArgumentError>()));
        await expectLater(w.lfsUnlock(''), throwsA(isA<ArgumentError>()));
        expect(git.calls, isEmpty);
      },
    );

    test('lock refuses an empty path, records no call', () async {
      await expectLater(w.lfsLock(''), throwsA(isA<ArgumentError>()));
      expect(git.calls, isEmpty);
    });

    test('list returns a failing result without throwing', () async {
      final w2 = GitWriter(_LockFailing(), '/r');
      final r = await w2.lfsLockList();
      expect(r.ok, isFalse);
      expect(r.stderr, 'locking is not supported');
    });

    test('lock and unlock throw GitException carrying the result', () async {
      final w2 = GitWriter(_LockFailing(), '/r');
      await expectLater(
        w2.lfsLock('a.psd'),
        throwsA(
          isA<GitException>().having(
            (e) => e.result?.stderr,
            'stderr',
            'locking is not supported',
          ),
        ),
      );
      await expectLater(w2.lfsUnlock('7'), throwsA(isA<GitException>()));
    });
  });

  group('changedPathsToPush', () {
    test(
      'upstream: three-dot diff, NUL split, blanks dropped, de-duplicated',
      () async {
        final g = _Names('a.psd\u0000b c.bin\u0000\u0000a.psd\u0000');
        final paths = await GitWriter(
          g,
          '/r',
        ).changedPathsToPush(upstream: 'origin/main');
        expect(paths, ['a.psd', 'b c.bin']);
        expect(g.calls.single, [
          'diff',
          '--name-only',
          '-z',
          'origin/main...HEAD',
        ]);
      },
    );

    test('no upstream: log of commits no remote has', () async {
      final g = _Names('x\u0000');
      final paths = await GitWriter(g, '/r').changedPathsToPush();
      expect(paths, ['x']);
      expect(g.calls.single, [
        'log',
        '--name-only',
        '-z',
        '--format=',
        'HEAD',
        '--not',
        '--remotes',
      ]);
    });

    test('a tag pushes with the log form on refs/tags/<tag>', () async {
      final g = _Names('x\u0000');
      await GitWriter(
        g,
        '/r',
      ).changedPathsToPush(upstream: 'origin/main', rev: 'refs/tags/v1');
      expect(g.calls.single, [
        'log',
        '--name-only',
        '-z',
        '--format=',
        'refs/tags/v1',
        '--not',
        '--remotes',
      ]);
    });

    test(
      'a dash-leading upstream makes no git call and returns nothing',
      () async {
        final g = _Names('x\u0000');
        final paths = await GitWriter(
          g,
          '/r',
        ).changedPathsToPush(upstream: '--output=/tmp/x');
        expect(paths, isEmpty);
        expect(g.calls, isEmpty);
      },
    );

    test('a failing git throws GitException', () async {
      final g = _Names('', code: 128);
      await expectLater(
        GitWriter(g, '/r').changedPathsToPush(upstream: 'origin/main'),
        throwsA(isA<GitException>()),
      );
    });
  });
}

class _Failing extends _Capture {
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
    timeouts.add(timeout);
    envs.add(environment);
    return args.first == 'lfs'
        ? const GitResult(2, '', 'boom')
        : const GitResult(0, '', '');
  }
}

class _Names extends _Capture {
  _Names(this.out, {this.code = 0});
  final String out;
  final int code;
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
    return GitResult(code, out, code == 0 ? '' : 'bad revision');
  }
}

class _LockFailing extends _Capture {
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
    timeouts.add(timeout);
    envs.add(environment);
    return args.first == 'lfs'
        ? const GitResult(2, '', 'locking is not supported')
        : const GitResult(0, '', '');
  }
}
