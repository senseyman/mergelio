import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _Capture implements GitService {
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
  final envs = <Map<String, String>?>[];

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
    expect(last(), ['lfs', 'track', '*.psd']);

    await w.lfsTrackFile('sub/odd [1].bin');
    expect(last(), ['lfs', 'track', '--filename', 'sub/odd [1].bin']);

    await w.lfsUntrack('*.psd');
    expect(last(), ['lfs', 'untrack', '*.psd']);

    final out = await w.lfsTrackList();
    expect(out, 'out');
    expect(last(), ['lfs', 'track']);

    await w.lfsInstallLocal();
    expect(last(), ['lfs', 'install', '--local']);
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
