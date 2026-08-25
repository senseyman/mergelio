import 'dart:convert';
import 'dart:io';

import 'commit_message.dart';
import 'git_service.dart';

/// Write-side git operations: staging the index and committing. Kept separate
/// from [GitReader] so the read and mutate paths stay distinct. Every method
/// throws [GitException] on failure so the UI can surface a toast.
class GitWriter {
  final GitService git;
  final String repoPath;
  GitWriter(this.git, this.repoPath);

  // Network ops can be slow (large transfers, slow links); give them room
  // well beyond the default read timeout so they are not killed mid-transfer.
  static const _netTimeout = Duration(minutes: 5);

  /// Resolved once per repository: the ssh command git would use anyway, which
  /// the watchdog options are appended to.
  Map<String, String>? _netEnvCache;

  Future<GitResult> _run(
    List<String> args, {
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) => git.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: environment,
    cancel: cancel,
  );

  Future<void> _ok(
    List<String> args,
    String what, {
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    final r = await _run(
      args,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
    );
    if (!r.ok) throw GitException(what, r);
  }

  /// Runs a command that talks to a remote, under the network timeout and with
  /// the ssh watchdog options in place.
  Future<void> _net(
    List<String> args,
    String what, {
    GitCancel? cancel,
  }) async => _ok(
    args,
    what,
    timeout: _netTimeout,
    environment: await _netEnv(),
    cancel: cancel,
  );

  /// git's own precedence: an inherited `GIT_SSH_COMMAND` first, then the
  /// repository's `core.sshCommand`, then plain ssh. Whichever wins becomes the
  /// base the watchdog options are added to, so a user's key or proxy survives.
  Future<Map<String, String>> _netEnv() async {
    if (_netEnvCache != null) return _netEnvCache!;
    var base = Platform.environment['GIT_SSH_COMMAND'];
    if (base == null || base.trim().isEmpty) {
      final configured = await _run(['config', '--get', 'core.sshCommand']);
      base = configured.ok ? configured.out : null;
    }
    return _netEnvCache = {'GIT_SSH_COMMAND': sshCommandWith(base)};
  }

  /// Fetches [remote] (or every remote when null), pruning deleted refs.
  Future<void> fetch({String? remote, GitCancel? cancel}) => _net(
    ['fetch', '--prune', if (remote != null) remote else '--all'],
    'git fetch',
    cancel: cancel,
  );

  /// Pulls the current branch's upstream; [rebase] replays local commits on top
  /// instead of creating a merge.
  Future<void> pull({bool rebase = false, GitCancel? cancel}) =>
      _net(['pull', if (rebase) '--rebase'], 'git pull', cancel: cancel);

  /// Prunes remote-tracking refs under [remote] that no longer exist upstream.
  Future<void> pruneRemote(String remote, {GitCancel? cancel}) =>
      _net(['remote', 'prune', remote], 'git remote prune', cancel: cancel);

  /// Registers [name] pointing at [url]. Fails when [name] is already taken.
  Future<void> addRemote(String name, String url) =>
      _ok(['remote', 'add', name, url], 'git remote add');

  /// Drops [name] along with its remote-tracking refs and branch config.
  Future<void> removeRemote(String name) =>
      _ok(['remote', 'remove', name], 'git remote remove');

  /// Renames [from] to [to], moving its remote-tracking refs with it.
  Future<void> renameRemote(String from, String to) =>
      _ok(['remote', 'rename', from, to], 'git remote rename');

  /// Points [name] at [url]; the fetch URL, which push inherits unless a
  /// separate push URL is configured.
  Future<void> setRemoteUrl(String name, String url) =>
      _ok(['remote', 'set-url', name, url], 'git remote set-url');

  /// Pushes the current branch. A branch with no upstream is published with
  /// `--set-upstream` to origin (or the only/first remote), so a first push
  /// works instead of failing. [force] uses `--force-with-lease`, which refuses
  /// to overwrite remote work the local ref has not seen.
  Future<void> push({bool force = false, GitCancel? cancel}) async {
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
    await _net(args, 'git push', cancel: cancel);
  }

  // --- Merge ops ------------------------------------------------------------

  /// Merges [branch] into the current branch. Throws on conflict (the caller
  /// inspects [GitReader.conflictedFiles] to open the Merge Tool) or error.
  Future<void> merge(
    String branch, {
    bool noFf = false,
    String? authorName,
    String? authorEmail,
  }) => _ok([
    ..._identity(authorName, authorEmail),
    'merge',
    if (noFf) '--no-ff',
    branch,
  ], 'git merge');

  Future<void> mergeAbort() => _ok(['merge', '--abort'], 'git merge --abort');

  /// Per-commit identity config args, prepended before a subcommand.
  static List<String> _identity(String? name, String? email) => [
    if (name != null) ...['-c', 'user.name=$name'],
    if (email != null) ...['-c', 'user.email=$email'],
  ];

  /// Completes an in-progress merge once conflicts are resolved and staged,
  /// attributing the merge commit to the active profile identity.
  Future<void> commitMerge({String? authorName, String? authorEmail}) => _ok([
    ..._identity(authorName, authorEmail),
    'commit',
    '--no-edit',
  ], 'git commit (merge)');

  // --- Interactive rebase ---------------------------------------------------

  /// Runs an interactive rebase onto [onto], driving the sequence editor with
  /// [todo] (so no terminal editor is needed). GIT_EDITOR is a no-op so squash
  /// messages auto-accept; reword is handled by exec lines in [todo]. [sign]
  /// signs every replayed commit. Throws on conflict (the caller inspects
  /// [GitReader.conflictedFiles]).
  Future<void> rebase(
    String onto,
    String todo, {
    String? authorName,
    String? authorEmail,
    bool sign = false,
  }) async {
    final tmp = await Directory.systemTemp.createTemp('mergelio_rebase_');
    final todoFile = File('${tmp.path}/todo');
    try {
      await todoFile.writeAsString(todo);
      await _ok(
        [
          ..._identity(authorName, authorEmail),
          'rebase',
          if (sign) '-S',
          '-i',
          onto,
        ],
        'git rebase',
        environment: {
          // Quoted: the editor line is run by a shell, and the temp path can
          // contain spaces (e.g. Windows user profiles).
          'GIT_SEQUENCE_EDITOR': 'cp "${todoFile.path}"',
          'GIT_EDITOR': 'true',
        },
      );
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  /// Straight (non-interactive) rebase of the current branch onto [onto].
  /// [sign] signs every replayed commit.
  Future<void> rebaseOnto(
    String onto, {
    String? authorName,
    String? authorEmail,
    bool sign = false,
  }) => _ok(
    [..._identity(authorName, authorEmail), 'rebase', if (sign) '-S', onto],
    'git rebase',
    environment: {'GIT_EDITOR': 'true'},
  );

  Future<void> rebaseAbort() =>
      _ok(['rebase', '--abort'], 'git rebase --abort');

  /// Continues a paused rebase after conflicts were resolved and staged.
  Future<void> rebaseContinue({String? authorName, String? authorEmail}) => _ok(
    [..._identity(authorName, authorEmail), 'rebase', '--continue'],
    'git rebase --continue',
    environment: {'GIT_EDITOR': 'true'},
  );

  // --- Branch ops -----------------------------------------------------------

  /// Creates branch [name], optionally pointing at [at] (a commit/ref).
  Future<void> createBranch(String name, {String? at}) =>
      _ok(['branch', name, ?at], 'git branch');

  /// Checks out [ref] (a branch or commit). [ignoreOtherWorktrees] overrides
  /// git's refusal to check out a branch already held by another worktree —
  /// callers only set it after the user has confirmed the collision, since it
  /// can leave two worktrees on the same branch with one HEAD going stale.
  Future<void> checkout(String ref, {bool ignoreOtherWorktrees = false}) => _ok(
    ['checkout', if (ignoreOtherWorktrees) '--ignore-other-worktrees', ref],
    'git checkout',
  );

  /// Creates a local branch [branch] tracking `[remote]/[branch]` and switches
  /// to it — the standard "check out a remote branch" flow.
  Future<void> checkoutTracking(String remote, String branch) => _ok([
    'switch',
    '-c',
    branch,
    '--track',
    '$remote/$branch',
  ], 'git switch --track');

  Future<void> renameBranch(String from, String to) =>
      _ok(['branch', '-m', from, to], 'git branch -m');

  /// Deletes branch [name]; [force] (`-D`) drops the merged-check.
  Future<void> deleteBranch(String name, {bool force = false}) =>
      _ok(['branch', force ? '-D' : '-d', name], 'git branch -d');

  /// Deletes [branch] on [remote]. The remote-tracking ref goes with it, so
  /// the branch leaves the sidebar on the next refresh.
  Future<void> deleteRemoteBranch(
    String remote,
    String branch, {
    GitCancel? cancel,
  }) => _net(
    ['push', remote, '--delete', branch],
    'git push --delete',
    cancel: cancel,
  );

  Future<void> setUpstream(String branch, String upstream) => _ok([
    'branch',
    '--set-upstream-to=$upstream',
    branch,
  ], 'git branch --set-upstream-to');

  // --- Tag ops --------------------------------------------------------------

  /// Creates tag [name] at [at] (default HEAD); an annotated tag when
  /// [message] is given.
  Future<void> createTag(String name, {String? at, String? message}) => _ok([
    'tag',
    if (message != null) ...['-m', message],
    name,
    ?at,
  ], 'git tag');

  Future<void> deleteTag(String name) => _ok(['tag', '-d', name], 'git tag -d');

  Future<void> pushTag(String name, {String remote = 'origin'}) =>
      _ok(['push', remote, name], 'git push tag', timeout: _netTimeout);

  // --- Commit-context ops ---------------------------------------------------

  Future<void> cherryPick(String sha) =>
      _ok(['cherry-pick', sha], 'git cherry-pick');

  /// Aborts an in-progress cherry-pick (used to back out of a conflict until
  /// the Merge Tool lands).
  Future<void> cherryPickAbort() =>
      _ok(['cherry-pick', '--abort'], 'git cherry-pick --abort');

  Future<void> revert(String sha) =>
      _ok(['revert', '--no-edit', sha], 'git revert');

  Future<void> revertAbort() =>
      _ok(['revert', '--abort'], 'git revert --abort');

  // — Submodules —

  Future<void> submoduleUpdate({
    String? path,
    bool init = false,
    bool recursive = false,
  }) => _ok(
    [
      'submodule',
      'update',
      if (init) '--init',
      if (recursive) '--recursive',
      if (path != null) ...['--', path],
    ],
    'git submodule update',
    timeout: _netTimeout,
  );

  Future<void> submoduleUpdateRemote(String path) => _ok(
    ['submodule', 'update', '--remote', '--', path],
    'git submodule update --remote',
    timeout: _netTimeout,
  );

  Future<void> submoduleAdd(String url, String path, {String? branch}) => _ok(
    [
      'submodule',
      'add',
      if (branch != null) ...['-b', branch],
      '--',
      url,
      path,
    ],
    'git submodule add',
    timeout: _netTimeout,
  );

  Future<void> submoduleSync({String? path}) => _ok([
    'submodule',
    'sync',
    if (path != null) ...['--', path],
  ], 'git submodule sync');

  Future<void> submoduleDeinit(String path, {bool force = false}) => _ok([
    'submodule',
    'deinit',
    if (force) '-f',
    '--',
    path,
  ], 'git submodule deinit');

  /// Fully removes a submodule: deinit, then `git rm` (drops the gitlink and
  /// the `.gitmodules` entry).
  Future<void> submoduleRemove(String path) async {
    await _ok([
      'submodule',
      'deinit',
      '-f',
      '--',
      path,
    ], 'git submodule deinit');
    await _ok(['rm', '-f', '--', path], 'git rm submodule');
  }

  /// Moves the current branch to [sha], discarding working-tree and index
  /// changes. Destructive — the caller must confirm first.
  Future<void> resetHard(String sha) =>
      _ok(['reset', '--hard', sha], 'git reset --hard');

  /// Moves HEAD to [sha] but leaves the index and working tree untouched — used
  /// to undo a commit (the committed changes return to the staging area).
  Future<void> resetSoft(String sha) =>
      _ok(['reset', '--soft', sha], 'git reset --soft');

  // --- Stash ops ------------------------------------------------------------

  /// [stagedOnly] stashes only what is in the index (`--staged`), leaving
  /// unstaged work in the tree.
  Future<void> stashPush({String? message, bool stagedOnly = false}) => _ok([
    'stash',
    'push',
    if (stagedOnly) '--staged',
    if (message != null) ...['-m', message],
  ], 'git stash push');

  Future<void> stashApply(String ref) =>
      _ok(['stash', 'apply', ref], 'git stash apply');

  Future<void> stashPop(String ref) =>
      _ok(['stash', 'pop', ref], 'git stash pop');

  /// Drops stash [ref], returning the dropped commit sha so the caller can
  /// offer an undo (re-store) toast.
  Future<String> stashDrop(String ref) async {
    final sha = (await _run(['rev-parse', ref])).out;
    await _ok(['stash', 'drop', ref], 'git stash drop');
    return sha;
  }

  /// Re-stores a previously dropped stash [sha] (undo of [stashDrop]).
  Future<void> stashStore(String sha) =>
      _ok(['stash', 'store', sha], 'git stash store');

  Future<void> stageFile(String path) => _ok(['add', '--', path], 'git add');

  Future<void> unstageFile(String path) =>
      _ok(['restore', '--staged', '--', path], 'git restore --staged');

  Future<void> stageAll() => _ok(['add', '-A'], 'git add -A');

  Future<void> unstageAll() => _ok(['reset', '-q', 'HEAD'], 'git reset');

  /// Applies [patch] to the index (staging), or reverses it (unstaging). The
  /// patch is written to a temp file because git reads it from a path, not
  /// this process's stdin.
  Future<void> applyToIndex(String patch, {bool reverse = false}) async {
    final dir = await Directory.systemTemp.createTemp('mergelio_stage_');
    final tmp = File('${dir.path}/stage.patch');
    try {
      await tmp.writeAsString(patch);
      await _ok([
        'apply',
        '--cached',
        if (reverse) '--reverse',
        tmp.path,
      ], 'git apply --cached');
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
        if (await dir.exists()) await dir.delete();
      } on FileSystemException {
        // Best-effort: a leaked temp file is not worth failing the op over.
      }
    }
  }

  /// Creates a commit. [amend] replaces the top commit; [sign] adds an SSH/GPG
  /// signature (requires the repo to be configured for it). [description] and
  /// [coauthors] are appended to the message body. [authorName]/[authorEmail],
  /// when given, set the commit identity for this commit (the active profile).
  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    List<String> coauthors = const [],
    String? authorName,
    String? authorEmail,
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
      // Per-commit identity via -c, applied before the subcommand.
      if (authorName != null) ...['-c', 'user.name=$authorName'],
      if (authorEmail != null) ...['-c', 'user.email=$authorEmail'],
      'commit',
      if (amend) '--amend',
      if (sign) '-S',
      '-m',
      body.toString(),
    ], 'git commit');
  }

  /// Rewrites the message of HEAD, leaving its tree alone. `--only` with no
  /// paths is git's way of amending the last commit *without* folding in
  /// whatever is already staged — a plain `--amend` would absorb it silently.
  Future<void> amendMessage(
    String summary, {
    String description = '',
    bool sign = false,
    String? authorName,
    String? authorEmail,
  }) => _ok([
    ..._identity(authorName, authorEmail),
    'commit',
    '--amend',
    '--only',
    if (sign) '-S',
    '-m',
    joinCommitMessage(summary, description),
  ], 'git commit --amend');

  /// Reverts [path] to its committed state, dropping staged and unstaged edits.
  /// Reverts every tracked file in the repository to HEAD, index and working
  /// tree alike. Untracked files are not touched — git does not consider them.
  Future<void> restoreAllFromHead() => _ok([
    'restore',
    '--staged',
    '--worktree',
    '--source=HEAD',
    '--',
    '.',
  ], 'git restore .');

  Future<void> restoreFromHead(String path) => _ok([
    'restore',
    '--staged',
    '--worktree',
    '--source=HEAD',
    '--',
    path,
  ], 'git restore');

  /// Applies [patch] to the working tree (not the index), or reverses it.
  Future<void> applyToWorktree(String patch, {bool reverse = false}) async {
    final dir = await Directory.systemTemp.createTemp('mergelio_discard_');
    final tmp = File('${dir.path}/discard.patch');
    try {
      await tmp.writeAsString(patch);
      await _ok(['apply', if (reverse) '--reverse', tmp.path], 'git apply');
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
        if (await dir.exists()) await dir.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }

  /// Creates a worktree at [path]. Exactly one of [newBranch], [existingBranch]
  /// or [detach] describes what it checks out; [startPoint] is the commit-ish a
  /// new branch or a detached head starts from.
  ///
  /// Combining two of them is a programming error, not a user error — git
  /// would reject the argv anyway, but its message ("options '-b' and
  /// '--detach' cannot be used together") would surface as a failed git
  /// operation instead of pointing at the caller. Throws [ArgumentError] up
  /// front so the mistake cannot reach a release build unnoticed.
  Future<void> addWorktree(
    String path, {
    String? newBranch,
    String? startPoint,
    String? existingBranch,
    bool detach = false,
  }) {
    final targets = [
      if (newBranch != null) 'newBranch',
      if (existingBranch != null) 'existingBranch',
      if (detach) 'detach',
    ];
    if (targets.length > 1) {
      throw ArgumentError(
        'git worktree add takes one checkout target, got ${targets.join(' + ')}',
      );
    }
    // An existing branch is itself the commit-ish; otherwise the start point
    // is, and either may be absent (git then uses HEAD).
    final commitish = existingBranch ?? startPoint;
    return _ok([
      'worktree',
      'add',
      if (newBranch != null) ...['-b', newBranch],
      if (detach) '--detach',
      path,
      ?commitish,
    ], 'git worktree add');
  }

  /// Removes the worktree at [path] and deletes its directory. Git refuses
  /// when the tree is dirty unless [force] is set.
  Future<void> removeWorktree(String path, {bool force = false}) => _ok([
    'worktree',
    'remove',
    if (force) '--force',
    path,
  ], 'git worktree remove');

  Future<void> moveWorktree(String from, String to) =>
      _ok(['worktree', 'move', from, to], 'git worktree move');

  /// Locks a worktree so it is never pruned — for one on a removable drive or
  /// a network mount that comes and goes.
  Future<void> lockWorktree(String path, {String? reason}) => _ok([
    'worktree',
    'lock',
    if (reason != null && reason.isNotEmpty) ...['--reason', reason],
    path,
  ], 'git worktree lock');

  Future<void> unlockWorktree(String path) =>
      _ok(['worktree', 'unlock', path], 'git worktree unlock');

  /// Drops administrative entries whose directories are gone. Returns git's
  /// own verbose report, which the UI shows verbatim — parsing it would only
  /// add a way to be wrong.
  ///
  /// `-v` writes its report to stderr, not stdout, even on success — so this
  /// reads [GitResult.stderr] rather than the more usual stdout.
  Future<String> pruneWorktrees({bool dryRun = false}) async {
    final r = await _run(['worktree', 'prune', '-v', if (dryRun) '--dry-run']);
    if (!r.ok) throw GitException('git worktree prune', r);
    return r.stderr;
  }
}
