import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/lfs.dart';

const _v = 'version https://git-lfs.github.com/spec/v1';
const _oid = '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
const _pointer = '$_v\noid sha256:$_oid\nsize 9\n';

/// Scripted answers keyed by the first argument (and by `--batch-check` vs
/// `--batch` for cat-file and by rev for grep).
class _Git implements GitService {
  final String gitVersion;
  final Map<String, GitResult> answers;
  final calls = <List<String>>[];
  final stdins = <String?>[];
  final timeouts = <Duration?>[];
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
      ['grep', ..., '--', _] when args.contains('filter=lfs') => 'attrs',
      ['grep', ...] => 'grep ${args[args.length - 1]}',
      ['cat-file', final mode, ...] => 'cat-file $mode',
      _ => args.first,
    };
    return answers[key] ?? const GitResult(1, '', 'unscripted');
  }

  @override
  Future<String> version() async => gitVersion;
  @override
  Future<bool> isRepository(String path) async => true;
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
      'cat-file --batch-check': GitResult(
        0,
        '$blob blob ${_pointer.length}\n',
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
        const ['gone.psd'],
      ),
    );
    expect(got, {'gone.psd'});
    expect(
      git.stdins[git.calls.indexWhere(
        (c) => c.length > 1 && c[1] == '--batch-check',
      )],
      'abc^:gone.psd\n',
    );
  });

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
