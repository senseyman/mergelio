import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// Records how each `git apply` was asked to run, so the environment and
/// timeout can be checked without relying on what locales the host has.
class _RecordingGit implements GitService {
  final calls =
      <({List<String> args, Map<String, String>? env, Duration? timeout})>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add((args: args, env: environment, timeout: timeout));
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
  const patch = [100, 105, 102, 102, 10];

  setUp(() {
    git = _RecordingGit();
    w = GitWriter(git, '/r');
  });

  test('every git apply runs with its messages untranslated', () async {
    await w.patchNumstat(patch);
    await w.checkPatch(patch, threeWay: true);
    await w.applyPatch(patch, threeWay: true);
    expect(git.calls, hasLength(3));
    for (final c in git.calls) {
      expect(c.args.first, 'apply');
      // Read by the 3-way conflict check, so it must never be translated.
      expect(c.env, containsPair('LC_MESSAGES', 'C'));
      expect(c.env, containsPair('LC_ALL', ''));
      expect(c.env, containsPair('LANGUAGE', ''));
    }
  });

  test('applying gets more than the default read timeout', () async {
    await w.applyPatch(patch, index: true);
    expect(git.calls.single.timeout, GitWriter.patchApplyTimeout);
    expect(
      GitWriter.patchApplyTimeout,
      greaterThan(const Duration(seconds: 30)),
    );
  });
}
