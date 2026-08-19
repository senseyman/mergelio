import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';

/// status() consumes `git status --porcelain=v2 -z` output. A truncated or
/// garbled entry (interrupted git, filesystem race) must be skipped, not crash
/// the whole listing with a RangeError.
class _StubGit implements GitService {
  final String stdout;
  _StubGit(this.stdout);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async => GitResult(0, stdout, '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  const nul = '\x00';
  const valid =
      '1 .M N... 100644 100644 100644 '
      '0000000000000000000000000000000000000000 '
      '0000000000000000000000000000000000000000 a.txt';

  Future<List<WorkingFile>> parse(String stdout) =>
      GitReader(_StubGit(stdout), '/r').status();

  test('truncated entries are skipped, valid ones survive', () async {
    final files = await parse(
      ['1 .M', '2 R.', 'u UU', '?', valid, ''].join(nul),
    );
    expect(files, hasLength(1));
    expect(files.single.path, 'a.txt');
    expect(files.single.worktree, GitChange.modified);
  });

  test('a well-formed listing still parses normally', () async {
    final files = await parse('$valid$nul? new.txt$nul');
    expect(files, hasLength(2));
    expect(files.map((f) => f.path), containsAll(['a.txt', 'new.txt']));
  });
}
