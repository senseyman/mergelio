// The navigator's git context: which paths git tracks, and which ones an
// ignore rule covers. Both read through the shared GitService, so they are
// tested against a fake rather than a repository.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/project_files.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];

  /// Keyed by the subcommand, e.g. 'ls-files' — the leading `-c key=value`
  /// pairs a caller may set are skipped.
  final Map<String, GitResult> results;
  _FakeGit(this.results);

  static String _subcommand(List<String> args) {
    var i = 0;
    while (i + 1 < args.length && args[i] == '-c') {
      i += 2;
    }
    return args[i];
  }

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return results[_subcommand(args)] ?? const GitResult(1, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _container(_FakeGit git, {List<Override> extra = const []}) {
  final c = ProviderContainer(
    overrides: [gitServiceProvider.overrideWithValue(git), ...extra],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('tracked paths', () {
    test('reads the NUL-separated list git prints', () async {
      final git = _FakeGit({
        'ls-files': const GitResult(
          0,
          'lib/main.dart\u0000README.md\u0000',
          '',
        ),
      });

      final tracked = await _container(
        git,
      ).read(trackedPathsProvider('/r').future);

      expect(tracked, {'lib/main.dart', 'README.md'});
      expect(git.calls.single, ['ls-files', '-z']);
    });

    test('a failed read reports unknown rather than nothing tracked', () async {
      // An empty set would paint every file untracked; null keeps the badges
      // off instead.
      final git = _FakeGit({'ls-files': const GitResult(128, '', 'boom')});

      final tracked = await _container(
        git,
      ).read(trackedPathsProvider('/r').future);

      expect(tracked, isNull);
    });
  });

  group('ignored entries', () {
    Override listing(DirListing value) =>
        dirListingProvider.overrideWith((ref, DirKey key) async => value);

    test('asks only about the children of the directory', () async {
      final git = _FakeGit({'check-ignore': const GitResult(0, 'build\n', '')});
      final c = _container(
        git,
        extra: [
          listing(
            const DirListing(
              entries: [
                DirEntry(name: 'build', isDir: true),
                DirEntry(name: 'lib', isDir: true),
              ],
            ),
          ),
        ],
      );

      final ignored = await c.read(
        ignoredInDirProvider(const DirKey('/r', '')).future,
      );

      expect(ignored, {'build'});
      expect(git.calls.single, [
        '-c',
        'core.quotepath=false',
        'check-ignore',
        '--no-index',
        '--',
        'build',
        'lib',
      ]);
    });

    test('nested children are asked about by repo-relative path', () async {
      final git = _FakeGit({
        'check-ignore': const GitResult(0, 'lib/gen.g.dart\n', ''),
      });
      final c = _container(
        git,
        extra: [
          listing(
            const DirListing(
              entries: [DirEntry(name: 'gen.g.dart', isDir: false)],
            ),
          ),
        ],
      );

      final ignored = await c.read(
        ignoredInDirProvider(const DirKey('/r', 'lib')).future,
      );

      expect(ignored, {'lib/gen.g.dart'});
    });

    test('exit 1 means nothing in the directory is ignored', () async {
      final git = _FakeGit({'check-ignore': const GitResult(1, '', '')});
      final c = _container(
        git,
        extra: [
          listing(
            const DirListing(entries: [DirEntry(name: 'lib', isDir: true)]),
          ),
        ],
      );

      expect(
        await c.read(ignoredInDirProvider(const DirKey('/r', '')).future),
        isEmpty,
      );
    });

    test('a failed check leaves everything unignored', () async {
      final git = _FakeGit({'check-ignore': const GitResult(128, '', 'boom')});
      final c = _container(
        git,
        extra: [
          listing(
            const DirListing(entries: [DirEntry(name: 'lib', isDir: true)]),
          ),
        ],
      );

      expect(
        await c.read(ignoredInDirProvider(const DirKey('/r', '')).future),
        isEmpty,
      );
    });

    test('an empty directory is not asked about at all', () async {
      final git = _FakeGit({});
      final c = _container(git, extra: [listing(const DirListing())]);

      expect(
        await c.read(ignoredInDirProvider(const DirKey('/r', '')).future),
        isEmpty,
      );
      expect(git.calls, isEmpty);
    });

    test('a long listing is asked about in chunks', () async {
      // One argument list per thousand entries keeps the command line under
      // the platform limit.
      final git = _FakeGit({'check-ignore': const GitResult(1, '', '')});
      final c = _container(
        git,
        extra: [
          listing(
            DirListing(
              entries: [
                for (var i = 0; i < 2500; i++)
                  DirEntry(name: 'f$i', isDir: false),
              ],
            ),
          ),
        ],
      );

      await c.read(ignoredInDirProvider(const DirKey('/r', '')).future);

      expect(git.calls.length, 3);
    });
  });
}
