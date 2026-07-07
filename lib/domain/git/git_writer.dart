import 'dart:io';

import 'git_service.dart';

/// Write-side git operations: staging the index and committing. Kept separate
/// from [GitReader] so the read and mutate paths stay distinct. Every method
/// throws [GitException] on failure so the UI can surface a toast.
class GitWriter {
  final GitService git;
  final String repoPath;
  const GitWriter(this.git, this.repoPath);

  Future<GitResult> _run(List<String> args) =>
      git.run(args, repoPath: repoPath);

  Future<void> _ok(List<String> args, String what) async {
    final r = await _run(args);
    if (!r.ok) throw GitException(what, r);
  }

  Future<void> stageFile(String path) => _ok(['add', '--', path], 'git add');

  Future<void> unstageFile(String path) =>
      _ok(['restore', '--staged', '--', path], 'git restore --staged');

  Future<void> stageAll() => _ok(['add', '-A'], 'git add -A');

  Future<void> unstageAll() => _ok(['reset', '-q', 'HEAD'], 'git reset');

  /// Applies [patch] to the index (staging), or reverses it (unstaging). The
  /// patch is written to a temp file because git reads it from a path, not
  /// this process's stdin.
  Future<void> applyToIndex(String patch, {bool reverse = false}) async {
    final tmp = await File(
      '${(await Directory.systemTemp.createTemp('mergelio_stage_')).path}/stage.patch',
    ).create();
    try {
      await tmp.writeAsString(patch);
      await _ok([
        'apply',
        '--cached',
        if (reverse) '--reverse',
        tmp.path,
      ], 'git apply --cached');
    } finally {
      if (await tmp.parent.exists()) {
        await tmp.parent.delete(recursive: true);
      }
    }
  }

  /// Creates a commit. [amend] replaces the top commit; [sign] adds an SSH/GPG
  /// signature (requires the repo to be configured for it). [description] and
  /// [coauthors] are appended to the message body.
  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    List<String> coauthors = const [],
  }) async {
    final body = StringBuffer(summary);
    if (description.trim().isNotEmpty) {
      body.write('\n\n${description.trim()}');
    }
    if (coauthors.isNotEmpty) {
      body.write('\n');
      for (final c in coauthors) {
        body.write('\nCo-authored-by: $c');
      }
    }
    await _ok([
      'commit',
      if (amend) '--amend',
      if (sign) '-S',
      '-m',
      body.toString(),
    ], 'git commit');
  }
}
