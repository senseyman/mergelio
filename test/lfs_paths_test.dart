import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart'
    show lfsAttributePattern, lfsPointerVersion;
import 'package:mergelio/state/lfs.dart';

const _v = 'version https://git-lfs.github.com/spec/v1';
const _oid = '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
const _pointer = '$_v\noid sha256:$_oid\nsize 9\n';

/// Scripted answers keyed by the first argument (and by `--batch-check` vs
/// `--batch` for cat-file and by rev for grep). A value can be a single
/// [GitResult], answered every time that key is asked for, or a
/// `List<GitResult>` answered in order — needed where the same key (e.g.
/// `cat-file --batch-check`) is asked more than once with a different stdin
/// each time.
class _Git implements GitService {
  final String gitVersion;
  final Map<String, Object> answers;
  final calls = <List<String>>[];
  final stdins = <String?>[];
  final timeouts = <Duration?>[];
  final _nextInQueue = <String, int>{};
  _Git(this.answers, {this.gitVersion = 'git version 2.45.0'});

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
    stdins.add(stdin);
    timeouts.add(timeout);
    final key = switch (args) {
      ['grep', ..., '--', _] when args.contains(lfsAttributePattern) => 'attrs',
      ['grep', ...] => 'grep ${args.lastWhere((a) => a != '--')}',
      ['cat-file', final mode, ...] => 'cat-file $mode',
      _ => args.first,
    };
    final answer = answers[key];
    if (answer is List<GitResult>) {
      final i = _nextInQueue[key] ?? 0;
      _nextInQueue[key] = i + 1;
      return i < answer.length ? answer[i] : answer.last;
    }
    if (answer is GitResult) return answer;
    return const GitResult(1, '', 'unscripted');
  }

  var versionCalls = 0;
  @override
  Future<String> version() async {
    versionCalls++;
    return gitVersion;
  }

  @override
  Future<bool> isRepository(String path) async => true;
}

class _RecordingSink implements LogSink {
  final lines = <String>[];

  @override
  void write(String line) => lines.add(line);
}

Future<Set<String>> _read(_Git git, LfsQuery q) async {
  final c = ProviderContainer(
    overrides: [gitServiceProvider.overrideWithValue(git)],
  );
  addTearDown(c.dispose);
  return c.read(lfsPathsProvider(q).future);
}

const _lfsRepo = GitResult(0, '.gitattributes\x00', '');

void main() {
  test('non-LFS repo short-circuits after one grep', () async {
    final git = _Git({'attrs': const GitResult(1, '', '')});
    final got = await _read(
      git,
      LfsQuery(const LfsSource(repoPath: '/r'), const ['a.psd']),
    );
    expect(got, isEmpty);
    expect(git.calls, hasLength(1));
    expect(git.calls.single.first, 'grep');
    expect(git.calls.single, contains(lfsAttributePattern));
    expect(git.calls.any((c) => c.first == 'check-attr'), isFalse);
    expect(git.calls.any((c) => c.first == 'cat-file'), isFalse);
  });

  test('no paths, no git', () async {
    final git = _Git({});
    expect(
      await _read(git, LfsQuery(const LfsSource(repoPath: '/r'), const [])),
      isEmpty,
    );
    expect(git.calls, isEmpty);
  });

  test('working tree asks check-attr with NUL-separated stdin', () async {
    final git = _Git({
      'attrs': _lfsRepo,
      'check-attr': const GitResult(
        0,
        'a b.psd\x00filter\x00lfs\x00c.txt\x00filter\x00unspecified\x00',
        '',
      ),
    });
    final got = await _read(
      git,
      LfsQuery(const LfsSource(repoPath: '/r'), const ['a b.psd', 'c.txt']),
    );
    expect(got, {'a b.psd'});
    expect(git.calls.last, ['check-attr', '-z', '--stdin', 'filter']);
    expect(git.stdins.last, 'a b.psd\x00c.txt\x00');
    expect(git.timeouts.last, lfsReadTimeout);
  });

  test('commit on git 2.40+ uses --source', () async {
    final git = _Git({
      'attrs': _lfsRepo,
      'check-attr': const GitResult(0, 'a.psd\x00filter\x00lfs\x00', ''),
    }, gitVersion: 'git version 2.40.0');
    final got = await _read(
      git,
      LfsQuery(
        const LfsSource(repoPath: '/r', rev: 'abc', parentRev: 'abc^'),
        const ['a.psd'],
      ),
    );
    expect(got, {'a.psd'});
    expect(git.calls.last, [
      'check-attr',
      '--source=abc',
      '-z',
      '--stdin',
      'filter',
    ]);
  });

  test('commit on git < 2.40 falls back to reading pointers', () async {
    const blob = '1111111111111111111111111111111111111111';
    final git = _Git({
      'attrs': _lfsRepo,
      'grep abc': const GitResult(0, 'abc:a.psd\x00abc:big.md\x00', ''),
      'cat-file --batch-check': GitResult(
        0,
        '$blob blob ${_pointer.length}\n'
            '2222222222222222222222222222222222222222 blob 99999\n',
        '',
      ),
      'cat-file --batch': GitResult(
        0,
        '$blob blob ${_pointer.length}\n$_pointer\n',
        '',
      ),
    }, gitVersion: 'git version 2.39.5');
    final got = await _read(
      git,
      LfsQuery(
        const LfsSource(repoPath: '/r', rev: 'abc', parentRev: 'abc^'),
        const ['a.psd', 'big.md', 'untouched.txt'],
      ),
    );
    expect(got, {'a.psd'});
    // Only the pointer-sized blob is read in full.
    expect(git.stdins.last, '$blob\n');
    expect(git.calls.any((c) => c.first == 'check-attr'), isFalse);
  });

  test('fallback grep keeps an option-shaped revision a revision', () async {
    // A branch may be named `-Osh`; left bare, grep reads it as its
    // open-files-in-pager option and runs `sh` on every match.
    final git = _Git({
      'attrs': _lfsRepo,
      'grep -Osh': const GitResult(1, '', ''),
    }, gitVersion: 'git version 2.39.5');
    await _read(
      git,
      LfsQuery(const LfsSource(repoPath: '/r', rev: '-Osh'), const ['a.psd']),
    );
    final scan = git.calls.where(
      (c) => c.first == 'grep' && !c.contains(lfsAttributePattern),
    );
    expect(scan.single, [
      'grep',
      '-l',
      '-z',
      '-F',
      '-e',
      lfsPointerVersion,
      '--end-of-options',
      '-Osh',
      '--',
    ]);
  });

  test('old git never passes an option-shaped parent to grep', () async {
    // Below git 2.24 there is no end-of-options marker, so a compare base
    // named like an option must be refused rather than handed to grep.
    final git = _Git({
      'attrs': _lfsRepo,
      'grep main': const GitResult(1, '', ''),
    }, gitVersion: 'git version 2.23.4');
    final got = await _read(
      git,
      LfsQuery(
        const LfsSource(repoPath: '/r', rev: 'main', parentRev: '-Osh'),
        const ['a.psd'],
      ),
    );
    expect(got, isEmpty);
    expect(git.calls.any((c) => c.contains('-Osh')), isFalse);
  });

  test('asks git its version once, not once per lookup', () async {
    final git = _Git({
      'attrs': _lfsRepo,
      'check-attr': const GitResult(0, 'a.psd\x00filter\x00lfs\x00', ''),
    });
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    for (final rev in const ['abc', 'def', 'abc..def']) {
      await c.read(
        lfsPathsProvider(
          LfsQuery(LfsSource(repoPath: '/r', rev: rev), const ['a.psd']),
        ).future,
      );
    }
    expect(git.versionCalls, 1);
  });

  test('fallback skips paths with a newline', () async {
    final git = _Git({
      'attrs': _lfsRepo,
      'grep abc': const GitResult(0, 'abc:odd\nname.bin\x00', ''),
    }, gitVersion: 'git version 2.39.5');
    final got = await _read(
      git,
      LfsQuery(const LfsSource(repoPath: '/r', rev: 'abc'), const [
        'odd\nname.bin',
      ]),
    );
    expect(got, isEmpty);
    expect(git.calls.any((c) => c.first == 'cat-file'), isFalse);
  });

  test('fallback finds paths deleted at rev in the parent', () async {
    const blob = '1111111111111111111111111111111111111111';
    final git = _Git({
      'attrs': _lfsRepo,
      'grep abc': const GitResult(1, '', ''),
      'grep abc^': const GitResult(0, 'abc^:gone.psd\x00', ''),
      'cat-file --batch-check': [
        // First: does gone.psd still exist at rev? It does not.
        const GitResult(0, 'abc:gone.psd missing\n', ''),
        // Second: size of the copy found in the parent.
        GitResult(0, '$blob blob ${_pointer.length}\n', ''),
      ],
      'cat-file --batch': GitResult(
        0,
        '$blob blob ${_pointer.length}\n$_pointer\n',
        '',
      ),
    }, gitVersion: 'git version 2.39.5');
    final got = await _read(
      git,
      LfsQuery(
        const LfsSource(repoPath: '/r', rev: 'abc', parentRev: 'abc^'),
        const ['gone.psd'],
      ),
    );
    expect(got, {'gone.psd'});
    final batchCheckStdins = [
      for (var i = 0; i < git.calls.length; i++)
        if (git.calls[i].length > 1 && git.calls[i][1] == '--batch-check')
          git.stdins[i],
    ];
    expect(batchCheckStdins, ['abc:gone.psd\n', 'abc^:gone.psd\n']);
  });

  test('parent fallback does not badge a path that still exists at rev as a '
      'plain blob', () async {
    const blob = '1111111111111111111111111111111111111111';
    final git = _Git({
      'attrs': _lfsRepo,
      // Neither path is a pointer at rev: a.psd was moved out of LFS
      // there, gone.psd was removed entirely.
      'grep abc': const GitResult(1, '', ''),
      'grep abc^': const GitResult(0, 'abc^:a.psd\x00abc^:gone.psd\x00', ''),
      'cat-file --batch-check': [
        // Existence check at rev: a.psd is still a real 17-byte blob,
        // gone.psd is gone.
        const GitResult(
          0,
          '3333333333333333333333333333333333333333 blob 17\n'
              'abc:gone.psd missing\n',
          '',
        ),
        // Size check, only reached for the path actually deleted at rev.
        GitResult(0, '$blob blob ${_pointer.length}\n', ''),
      ],
      'cat-file --batch': GitResult(
        0,
        '$blob blob ${_pointer.length}\n$_pointer\n',
        '',
      ),
    }, gitVersion: 'git version 2.39.5');
    final got = await _read(
      git,
      LfsQuery(
        const LfsSource(repoPath: '/r', rev: 'abc', parentRev: 'abc^'),
        const ['a.psd', 'gone.psd'],
      ),
    );
    expect(got, {'gone.psd'});
  });

  test(
    'rev grep failure other than no-match is logged and yields no badges',
    () async {
      final sink = _RecordingSink();
      final previous = appLog;
      appLog = AppLogger(sink: sink);
      addTearDown(() => appLog = previous);

      final git = _Git({
        'attrs': _lfsRepo,
        'grep abc': const GitResult(128, '', 'fatal: bad object abc'),
      }, gitVersion: 'git version 2.39.5');
      final got = await _read(
        git,
        LfsQuery(const LfsSource(repoPath: '/r', rev: 'abc'), const ['a.psd']),
      );
      expect(got, isEmpty);
      expect(sink.lines, isNotEmpty);
      expect(sink.lines.single, contains('[/r]'));
    },
  );

  test('check-attr failure yields no badges', () async {
    final git = _Git({
      'attrs': _lfsRepo,
      'check-attr': const GitResult(128, '', 'fatal'),
    });
    expect(
      await _read(
        git,
        LfsQuery(const LfsSource(repoPath: '/r'), const ['a.psd']),
      ),
      isEmpty,
    );
  });

  test('queries compare by value', () {
    expect(
      LfsQuery(const LfsSource(repoPath: '/r'), ['a', 'b']),
      LfsQuery(const LfsSource(repoPath: '/r'), ['a', 'b']),
    );
    expect(
      LfsQuery(const LfsSource(repoPath: '/r'), ['a', 'b']).hashCode,
      LfsQuery(const LfsSource(repoPath: '/r'), ['a', 'b']).hashCode,
    );
  });
}
