import 'dart:convert';
import 'dart:io';

import 'git_service.dart';

/// Write-side git operations: staging the index and committing. Kept separate
/// from [GitReader] so the read and mutate paths stay distinct. Every method
/// throws [GitException] on failure so the UI can surface a toast.
class GitWriter {
  final GitService git;
  final String repoPath;
  const GitWriter(this.git, this.repoPath);

  // Network ops can be slow (large transfers, slow links); give them room
  // well beyond the default read timeout so they are not killed mid-transfer.
  static const _netTimeout = Duration(minutes: 5);

  Future<GitResult> _run(List<String> args, {Duration? timeout}) =>
      git.run(args, repoPath: repoPath, timeout: timeout);

  Future<void> _ok(List<String> args, String what, {Duration? timeout}) async {
    final r = await _run(args, timeout: timeout);
    if (!r.ok) throw GitException(what, r);
  }

  /// Fetches [remote] (or every remote when null), pruning deleted refs.
  Future<void> fetch({String? remote}) => _ok(
    ['fetch', '--prune', if (remote != null) remote else '--all'],
    'git fetch',
    timeout: _netTimeout,
  );

  /// Pulls the current branch's upstream; [rebase] replays local commits on top
  /// instead of creating a merge.
  Future<void> pull({bool rebase = false}) =>
      _ok(['pull', if (rebase) '--rebase'], 'git pull', timeout: _netTimeout);

  /// Pushes the current branch. A branch with no upstream is published with
  /// `--set-upstream` to origin (or the only/first remote), so a first push
  /// works instead of failing. [force] uses `--force-with-lease`, which refuses
  /// to overwrite remote work the local ref has not seen.
  Future<void> push({bool force = false}) async {
    final hasUpstream = (await _run([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ])).ok;
    final args = <String>['push', if (force) '--force-with-lease'];
    if (!hasUpstream) {
      final branch = (await _run(['rev-parse', '--abbrev-ref', 'HEAD'])).out;
      if (branch == 'HEAD') {
        throw GitException('cannot push in detached HEAD state');
      }
      final remotes = const LineSplitter()
          .convert((await _run(['remote'])).stdout)
          .where((s) => s.isNotEmpty)
          .toList();
      if (remotes.isEmpty) {
        throw GitException('no remote configured to push to');
      }
      final remote = remotes.contains('origin') ? 'origin' : remotes.first;
      args.addAll(['--set-upstream', remote, branch]);
    }
    await _ok(args, 'git push', timeout: _netTimeout);
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
