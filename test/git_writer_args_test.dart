import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// A submodule or file path is repo-controlled data: a crafted checkout can
/// contain one that starts with `-`. Every writer command that places a path
/// after options must emit a `--` separator so git parses it as a pathspec,
/// never as an option.
class _CapturingGit implements GitService {
  final calls = <List<String>>[];
  final environments = <Map<String, String>?>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    environments.add(environment);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _CapturingGit git;
  late GitWriter writer;

  setUp(() {
    git = _CapturingGit();
    writer = GitWriter(git, '/repo');
  });

  group('submodule paths are separated from options with --', () {
    test('submoduleRemove', () async {
      await writer.submoduleRemove('-rf');
      expect(git.calls[0], ['submodule', 'deinit', '-f', '--', '-rf']);
      expect(git.calls[1], ['rm', '-f', '--', '-rf']);
    });

    test('submoduleDeinit', () async {
      await writer.submoduleDeinit('--all', force: true);
      expect(git.calls.single, ['submodule', 'deinit', '-f', '--', '--all']);
    });

    test('submoduleUpdate with a path', () async {
      await writer.submoduleUpdate(path: '--remote', init: true);
      expect(git.calls.single, [
        'submodule',
        'update',
        '--init',
        '--',
        '--remote',
      ]);
    });

    test('submoduleUpdate without a path adds no separator', () async {
      await writer.submoduleUpdate();
      expect(git.calls.single, ['submodule', 'update']);
    });

    test('submoduleUpdateRemote', () async {
      await writer.submoduleUpdateRemote('-f');
      expect(git.calls.single, ['submodule', 'update', '--remote', '--', '-f']);
    });

    test('submoduleSync with a path', () async {
      await writer.submoduleSync(path: '-f');
      expect(git.calls.single, ['submodule', 'sync', '--', '-f']);
    });

    test('submoduleAdd', () async {
      await writer.submoduleAdd('https://x.test/r.git', 'sub', branch: 'main');
      expect(git.calls.single, [
        'submodule',
        'add',
        '-b',
        'main',
        '--',
        'https://x.test/r.git',
        'sub',
      ]);
    });
  });

  group('interactive rebase sequence editor', () {
    test('quotes the todo path so spaces in the temp dir survive', () async {
      await writer.rebase('main', 'pick abc');
      final env = git.environments.single!;
      final editor = env['GIT_SEQUENCE_EDITOR']!;
      // cp "<path>" — quoted, so a temp dir containing spaces still works.
      expect(editor, matches(RegExp(r'^cp "[^"]+"$')));
      expect(env['GIT_EDITOR'], 'true');
    });
  });
}
