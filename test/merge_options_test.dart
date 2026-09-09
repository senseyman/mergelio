import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// A git that records the argument lists it was handed and reports success,
/// so flag composition can be asserted without running a merge.
class _CapturingGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<GitResult> run(List<String> args) => svc.run(args, repoPath: dir.path);

  Future<void> g(List<String> args) async {
    final r = await run(args);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> write(String name, String content) =>
      File('${dir.path}/$name').writeAsString(content);

  GitReader reader() => GitReader(svc, dir.path);
  GitWriter writer() => GitWriter(svc, dir.path);

  Future<String> head() async => (await run(['rev-parse', 'HEAD'])).out;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_mergeopt_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('a.txt', 'base\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);

    // feature adds a file and rewrites the shared line; main rewrites it too,
    // so a plain merge of the two conflicts.
    await g(['checkout', '-q', '-b', 'feature']);
    await write('a.txt', 'feature\n');
    await write('b.txt', 'from feature\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'feature edit']);

    await g(['checkout', '-q', 'main']);
    await write('a.txt', 'main\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'main edit']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('squash', () {
    test('stages the merged tree without creating a commit', () async {
      await g(['checkout', '-q', '-b', 'other', 'main']);
      await write('c.txt', 'from other\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'add c']);
      await g(['checkout', '-q', 'main']);
      final before = await head();

      await writer().merge('other', squash: true);

      expect(await head(), before, reason: 'squash must not commit');
      expect(File('${dir.path}/c.txt').existsSync(), isTrue);
      expect((await run(['diff', '--cached', '--name-only'])).out, 'c.txt');
      // No MERGE_HEAD: the follow-up commit is an ordinary one, not a merge.
      expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isFalse);
    });

    test('a conflicted squash merge can still be aborted', () async {
      await expectLater(
        writer().merge('feature', squash: true),
        throwsA(isA<GitException>()),
      );
      expect(await reader().conflictedFiles(), ['a.txt']);
      // A squash writes no MERGE_HEAD, so plain `git merge --abort` refuses:
      // the abort path has to fall back to git's own recovery for that state.
      expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isFalse);

      await writer().mergeAbort();

      expect(await reader().conflictedFiles(), isEmpty);
      expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
    });

    test('aborting leaves unrelated uncommitted work alone', () async {
      await write('untracked.txt', 'mine\n');
      await expectLater(
        writer().merge('feature', squash: true),
        throwsA(isA<GitException>()),
      );

      await writer().mergeAbort();

      expect(await File('${dir.path}/untracked.txt').readAsString(), 'mine\n');
    });

    test('is not combined with --no-ff, which git rejects', () async {
      final git = _CapturingGit();
      await GitWriter(git, '/repo').merge('other', noFf: true, squash: true);
      expect(git.calls.single, contains('--squash'));
      expect(git.calls.single, isNot(contains('--no-ff')));
    });
  });

  group('no-commit', () {
    test('leaves the merge staged with MERGE_HEAD set', () async {
      await g(['checkout', '-q', '-b', 'other', 'main']);
      await write('c.txt', 'from other\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'add c']);
      await g(['checkout', '-q', 'main']);
      final before = await head();

      // The app always merges --no-ff; without it this would fast-forward and
      // there would be no staged merge to review.
      await writer().merge('other', noFf: true, noCommit: true);

      expect(await head(), before);
      expect(File('${dir.path}/c.txt').existsSync(), isTrue);
      // MERGE_HEAD still set, so the user's commit is a real merge commit.
      expect(File('${dir.path}/.git/MERGE_HEAD').existsSync(), isTrue);
    });
  });

  group('strategy option', () {
    test('ours resolves conflicting hunks to the current branch', () async {
      await writer().merge('feature', favor: MergeFavor.ours);

      expect(await reader().conflictedFiles(), isEmpty);
      expect(await File('${dir.path}/a.txt').readAsString(), 'main\n');
      // Non-overlapping work from the other side still lands.
      expect(File('${dir.path}/b.txt').existsSync(), isTrue);
    });

    test('theirs resolves conflicting hunks to the merged branch', () async {
      await writer().merge('feature', favor: MergeFavor.theirs);

      expect(await reader().conflictedFiles(), isEmpty);
      expect(await File('${dir.path}/a.txt').readAsString(), 'feature\n');
    });

    test('none passes no -X flag', () async {
      final git = _CapturingGit();
      await GitWriter(git, '/repo').merge('feature');
      expect(git.calls.single, isNot(contains('-X')));
    });
  });
}
