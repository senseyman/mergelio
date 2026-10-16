import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// Records the timeout and cancel handle each command was given, so the limit
/// a hook-running command gets can be checked without a hook slow enough to
/// hit it.
class _RecordingGit implements GitService {
  final calls = <({List<String> args, Duration? timeout, GitCancel? cancel})>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add((args: args, timeout: timeout, cancel: cancel));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _RecordingGit git;
  late GitWriter w;

  setUp(() {
    git = _RecordingGit();
    w = GitWriter(git, '/r');
  });

  test('the hook ceiling is longer than the ordinary default', () {
    expect(GitWriter.hookTimeout, greaterThan(const Duration(seconds: 30)));
  });

  final ops = <String, Future<void> Function(GitWriter, GitCancel?)>{
    'commit': (w, c) => w.commit('msg', cancel: c),
    'amend message': (w, c) => w.amendMessage('msg', cancel: c),
    'merge': (w, c) => w.merge('topic', cancel: c),
    'cherry-pick --continue': (w, c) => w.cherryPickContinue(cancel: c),
    'revert --continue': (w, c) => w.revertContinue(cancel: c),
  };

  for (final MapEntry(key: name, value: op) in ops.entries) {
    test('$name runs under the hook ceiling', () async {
      await op(w, null);
      expect(git.calls.single.timeout, GitWriter.hookTimeout);
    });

    test('$name hands git the cancel handle', () async {
      final cancel = GitCancel();
      await op(w, cancel);
      expect(git.calls.single.cancel, same(cancel));
    });
  }
}
