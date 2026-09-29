import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart' show lfsAttributePattern;
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:path/path.dart' as p;

/// Answers by the first argument; records every call with its options.
class _Git implements GitService {
  final Map<String, GitResult> byCommand;
  final String gitVersion;
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
  final stdins = <String?>[];
  // ignore: unused_element_parameter
  _Git(this.byCommand, {this.gitVersion = 'git version 2.45.0'});

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
    stdins.add(stdin);
    final key = args.first == 'lfs' ? 'lfs' : args.first;
    return byCommand[key] ?? const GitResult(1, '', 'no');
  }

  @override
  Future<String> version() async => gitVersion;
  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _c(_Git git) {
  final c = ProviderContainer(
    overrides: [gitServiceProvider.overrideWithValue(git)],
  );
  addTearDown(c.dispose);
  return c;
}

const _wt = LfsSource(repoPath: '/r');

void main() {
  group('lfsToolProvider', () {
    test('version when git-lfs answers', () async {
      final git = _Git({'lfs': const GitResult(0, 'git-lfs/3.5.1 (x)\n', '')});
      expect(await _c(git).read(lfsToolProvider.future), '3.5.1');
      expect(git.calls.single, ['lfs', 'version']);
      expect(git.timeouts.single, lfsReadTimeout);
    });
    test('null when git-lfs is not a git command', () async {
      final git = _Git({'lfs': const GitResult(1, '', "'lfs' is not")});
      expect(await _c(git).read(lfsToolProvider.future), isNull);
    });
    test('empty lfs version is missing', () async {
      final git = _Git({'lfs': const GitResult(0, '', '')});
      expect(await _c(git).read(lfsToolProvider.future), isNull);
    });
  });

  group('lfsRepoProvider', () {
    test('true when a tracked .gitattributes names filter=lfs', () async {
      final git = _Git({'grep': const GitResult(0, '.gitattributes\x00', '')});
      expect(await _c(git).read(lfsRepoProvider(_wt).future), isTrue);
      expect(git.calls.single, [
        'grep',
        '-l',
        '-z',
        '-E',
        '-e',
        lfsAttributePattern,
        '--',
        ':(glob)**/.gitattributes',
      ]);
      expect(git.timeouts.single, lfsReadTimeout);
    });
    test('greps the revision itself for a commit source', () async {
      final git = _Git({
        'grep': const GitResult(0, 'abc:.gitattributes\x00', ''),
      });
      final src = const LfsSource(repoPath: '/r', rev: 'abc');
      expect(await _c(git).read(lfsRepoProvider(src).future), isTrue);
      expect(git.calls.single, [
        'grep',
        '-l',
        '-z',
        '-E',
        '-e',
        lfsAttributePattern,
        '--end-of-options',
        'abc',
        '--',
        ':(glob)**/.gitattributes',
      ]);
    });
    test('a revision shaped like an option stays a revision', () async {
      // A branch may be named `-Osh`; left bare, grep reads it as its
      // open-files-in-pager option and runs `sh` on every match.
      final git = _Git({'grep': const GitResult(1, '', '')});
      final src = const LfsSource(repoPath: '/r', rev: '-Osh');
      await _c(git).read(lfsRepoProvider(src).future);
      final args = git.calls.single;
      final at = args.indexOf('-Osh');
      expect(at, greaterThan(0));
      expect(args[at - 1], '--end-of-options');
    });
    test('names a plain revision bare on git older than 2.24', () async {
      final git = _Git({
        'grep': const GitResult(0, 'abc:.gitattributes\x00', ''),
      }, gitVersion: 'git version 2.23.4');
      final src = const LfsSource(repoPath: '/r', rev: 'abc');
      expect(await _c(git).read(lfsRepoProvider(src).future), isTrue);
      expect(git.calls.single, isNot(contains('--end-of-options')));
      expect(git.calls.single, containsAllInOrder(['abc', '--']));
    });
    test('refuses an option-shaped revision on git older than 2.24', () async {
      final sink = _RecordingSink();
      final previous = appLog;
      appLog = AppLogger(sink: sink);
      addTearDown(() => appLog = previous);
      final git = _Git({
        'grep': const GitResult(0, '-Osh:.gitattributes\x00', ''),
      }, gitVersion: 'git version 2.23.4');
      final src = const LfsSource(repoPath: '/r', rev: '-Osh');
      expect(await _c(git).read(lfsRepoProvider(src).future), isFalse);
      expect(git.calls.where((c) => c.first == 'grep'), isEmpty);
      expect(sink.lines.join('\n'), contains('[/r]'));
    });
    test('logs a grep that fails rather than finding nothing', () async {
      final sink = _RecordingSink();
      final previous = appLog;
      appLog = AppLogger(sink: sink);
      addTearDown(() => appLog = previous);
      final git = _Git({'grep': const GitResult(129, '', 'unknown option')});
      expect(await _c(git).read(lfsRepoProvider(_wt).future), isFalse);
      expect(sink.lines.single, contains('[/r]'));
    });
    test('false on no match (exit 1)', () async {
      final git = _Git({'grep': const GitResult(1, '', '')});
      expect(await _c(git).read(lfsRepoProvider(_wt).future), isFalse);
    });
    test('empty successful grep is not LFS', () async {
      final git = _Git({'grep': const GitResult(0, '', '')});
      expect(await _c(git).read(lfsRepoProvider(_wt).future), isFalse);
    });
  });

  test('lfsObjectsDirProvider honours lfs.storage', () async {
    final git = _Git({
      'rev-parse': const GitResult(0, '.git\n', ''),
      'config': const GitResult(0, 'big\n', ''),
    });
    expect(
      await _c(git).read(lfsObjectsDirProvider('/r').future),
      p.join('/r', '.git', 'big', 'objects'),
    );
  });

  test('lfsObjectsDirProvider without lfs.storage (config exit 1)', () async {
    final git = _Git({'rev-parse': const GitResult(0, '.git\n', '')});
    expect(
      await _c(git).read(lfsObjectsDirProvider('/r').future),
      p.join('/r', '.git', 'lfs', 'objects'),
    );
  });

  test('lfsAttrsStamp changes only with .gitattributes entries', () {
    const other = WorkingFile(path: 'a.txt', worktree: GitChange.modified);
    const root = WorkingFile(
      path: '.gitattributes',
      worktree: GitChange.modified,
    );
    const nested = WorkingFile(
      path: 'art/.gitattributes',
      index: GitChange.added,
    );
    expect(lfsAttrsStamp(const [other]), '');
    expect(lfsAttrsStamp(const [other, root]), isNot(''));
    expect(
      lfsAttrsStamp(const [root, nested]),
      isNot(lfsAttrsStamp(const [root])),
    );
  });

  test('lfsSourceFor maps diff targets', () {
    expect(
      lfsSourceFor(const DiffTarget(repoPath: '/r', path: 'a')),
      const LfsSource(repoPath: '/r'),
    );
    expect(
      lfsSourceFor(const DiffTarget(repoPath: '/r', path: 'a', commitSha: 'c')),
      const LfsSource(repoPath: '/r', rev: 'c', parentRev: 'c^'),
    );
    expect(
      lfsSourceFor(
        const DiffTarget(
          repoPath: '/r',
          path: 'a',
          commitSha: 'c',
          baseRev: 'b',
        ),
      ),
      const LfsSource(repoPath: '/r', rev: 'c', parentRev: 'b'),
    );
  });

  test('only a full sha is immutable', () {
    expect(const LfsSource(repoPath: '/r').isImmutable, isFalse);
    expect(const LfsSource(repoPath: '/r', rev: 'main').isImmutable, isFalse);
    expect(LfsSource(repoPath: '/r', rev: 'a' * 40).isImmutable, isTrue);
  });

  group('lfsObjectPresentProvider', () {
    late Directory objectsDir;

    setUp(() {
      objectsDir = Directory.systemTemp.createTempSync('lfs_objects_test_');
      addTearDown(() {
        if (objectsDir.existsSync()) objectsDir.deleteSync(recursive: true);
      });
    });

    ProviderContainer containerFor(String dir) {
      final c = ProviderContainer(
        overrides: [
          lfsObjectsDirProvider.overrideWith((ref, repoPath) async => dir),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('true when the object file is on disk', () async {
      final oid = 'a' * 64;
      final shard = Directory(
        p.join(objectsDir.path, oid.substring(0, 2), oid.substring(2, 4)),
      )..createSync(recursive: true);
      File(p.join(shard.path, oid)).writeAsStringSync('blob');

      final c = containerFor(objectsDir.path);
      expect(
        await c.read(
          lfsObjectPresentProvider((repoPath: '/r', oid: oid)).future,
        ),
        isTrue,
      );
    });

    test('false when the object file is missing', () async {
      final oid = 'b' * 64;
      final c = containerFor(objectsDir.path);
      expect(
        await c.read(
          lfsObjectPresentProvider((repoPath: '/r', oid: oid)).future,
        ),
        isFalse,
      );
    });

    test(
      'false, not an AsyncError, when the oid is too short to shard',
      () async {
        final sink = _RecordingSink();
        final previous = appLog;
        appLog = AppLogger(sink: sink);
        addTearDown(() => appLog = previous);

        final c = containerFor(objectsDir.path);
        expect(
          await c.read(
            lfsObjectPresentProvider((repoPath: '/r', oid: 'ab')).future,
          ),
          isFalse,
        );
        expect(sink.lines, isNotEmpty);
        expect(sink.lines.single, contains('[/r]'));
      },
    );

    test('false, not an AsyncError, on an empty oid', () async {
      final sink = _RecordingSink();
      final previous = appLog;
      appLog = AppLogger(sink: sink);
      addTearDown(() => appLog = previous);

      final c = containerFor(objectsDir.path);
      expect(
        await c.read(
          lfsObjectPresentProvider((repoPath: '/r', oid: '')).future,
        ),
        isFalse,
      );
      expect(sink.lines, isNotEmpty);
    });
  });
}

class _RecordingSink implements LogSink {
  final lines = <String>[];

  @override
  void write(String line) => lines.add(line);
}
