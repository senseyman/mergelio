import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'askpass.dart';
import 'commit_message.dart';
import 'git_service.dart';
import 'hooks.dart';
import 'notes.dart';
import 'rebase_plan.dart';
import 'stash.dart';

/// The flag [shell] wants in front of a command string.
///
/// Read off the shell itself, never off the platform: on Windows `$SHELL` is
/// commonly set, by Git Bash or MSYS, and that shell is a POSIX one. Handing
/// it `/c` makes it treat the flag as a path to run and the command as an
/// argument, so the run fails on every commit for a reason nothing reports.
/// Only `cmd` takes `/c`, whichever way its path is spelled.
String shellCommandFlag(String shell) {
  final name = shell.split(RegExp(r'[/\\]')).last.toLowerCase();
  final base = name.endsWith('.exe')
      ? name.substring(0, name.length - 4)
      : name;
  return base == 'cmd' ? '/c' : '-c';
}

/// Environment for a `git bisect run`, pinning the language git reports its
/// own endings in.
///
/// git translates those endings — measured, git 2.55.0: `error: bisect run
/// cannot continue any more` comes back as `помилка: неможливо продовжити
/// бісекцію` under uk_UA and `erreur : la bissection ne peut plus continuer`
/// under fr_FR — and it ships translations for twenty languages including
/// this app's own Ukrainian. Reading those endings out of English prose
/// therefore fails for real users, not hypothetical ones.
///
/// Only the message category is pinned. The user's own command inherits this
/// environment, and forcing the whole locale to C would change how it handles
/// characters, not just which language it complains in — enough to make a
/// suite that reads UTF-8 filenames start failing. `LC_CTYPE` and `LANG` are
/// left exactly as the user has them, so the only thing that changes for the
/// command is the language of any diagnostics it prints, which nothing here
/// reads anyway.
///
/// All three keys are needed. gettext takes `LANGUAGE` ahead of every `LC_*`,
/// and an `LC_ALL` in the environment overrides `LC_MESSAGES`, so pinning
/// `LC_MESSAGES` alone is defeated by either of them. An empty value reads as
/// unset, which is why these clear rather than set.
const bisectRunMessageEnv = {'LC_ALL': '', 'LC_MESSAGES': 'C', 'LANGUAGE': ''};

/// Arguments for `git bisect run`, with [command] handed to a shell as a
/// single string.
///
/// Splitting on whitespace would break quoting, pipes and shell builtins, so
/// the user's line goes through verbatim. The shell matches the one the
/// terminal uses, so a command behaves the same in both places.
List<String> bisectRunArgs(String command) {
  final shell =
      Platform.environment['SHELL'] ??
      (Platform.isWindows ? 'cmd.exe' : '/bin/sh');
  return ['bisect', 'run', shell, shellCommandFlag(shell), command];
}

/// Which side wins a hunk both branches changed (`-X ours` / `-X theirs`).
/// Only overlapping hunks are decided this way; work the two sides did in
/// different places is still combined.
enum MergeFavor { none, ours, theirs }

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

  /// Ceiling for deepening a shallow clone: it downloads the rest of the
  /// history, which on a big repository is most of a full clone.
  static const _unshallowTimeout = Duration(minutes: 30);

  /// Ceiling for `git bisect run`, whose duration is the user's own command
  /// multiplied by the number of steps left — a test suite over a deep history
  /// legitimately takes hours.
  ///
  /// Explicit rather than omitted: leaving it off does not mean "no limit", it
  /// means the service's ordinary default, which would kill a real run within
  /// the first commit or two. There is no way to ask for no limit at all, and a
  /// figure this far out is one nothing reaches on purpose while still stopping
  /// an abandoned run from holding its lane until the app is quit. Cancelling
  /// remains the way a run is actually stopped.
  static const _bisectRunTimeout = Duration(hours: 12);

  /// Ceiling for a git-lfs transfer. Objects can run into gigabytes over a
  /// slow link, far past the ordinary network timeout; cancelling remains
  /// the way out of one that is actually stuck.
  static const lfsTransferTimeout = Duration(hours: 2);

  /// Ceiling for a git-lfs command that stays on this machine (track, untrack,
  /// listing patterns, installing hooks). git-lfs scans the repository for
  /// some of these, which can outlast the ordinary default on a large tree.
  static const lfsLocalTimeout = Duration(seconds: 60);

  /// Ceiling for a call to the LFS lock server. One unlock can be several
  /// requests (git-lfs looks the lock up before releasing it), and a distant
  /// or ssh-authenticated server can be slow; a stuck call can be cancelled.
  static const lfsLockTimeout = Duration(minutes: 5);

  /// Ceiling for one `git apply` over a picked patch file. A large series,
  /// or a 3-way merge that has to read many blobs on a slow volume, can
  /// outlast the ordinary default.
  static const patchApplyTimeout = Duration(minutes: 5);

  /// Ceiling for a command that runs the user's commit hooks. A pre-commit
  /// running a linter or a test suite, or a signed commit waiting on a GPG
  /// passphrase prompt, routinely outlasts the ordinary default; cancelling
  /// remains the way out of one that is actually stuck.
  static const hookTimeout = Duration(minutes: 30);

  /// Resolved once per repository: the ssh command git would use anyway, plus
  /// what a command that hits an authentication prompt needs.
  Map<String, String>? _netEnvCache;

  Future<GitResult> _run(
    List<String> args, {
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => git.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: environment,
    cancel: cancel,
    stdin: stdin,
  );

  Future<void> _ok(
    List<String> args,
    String what, {
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final r = await _run(
      args,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
      stdin: stdin,
    );
    if (!r.ok) throw GitException(what, r);
  }

  /// Runs a command that talks to a remote, under the network timeout and with
  /// the ssh watchdog options in place.
  Future<void> _net(
    List<String> args,
    String what, {
    GitCancel? cancel,
    Duration timeout = _netTimeout,
  }) async => _ok(
    args,
    what,
    timeout: timeout,
    environment: await _netEnv(),
    cancel: cancel,
  );

  /// The ssh watchdog options over whatever ssh command the user configured,
  /// plus the credential prompt wiring. Resolved once per repository.
  Future<Map<String, String>> _netEnv() async => _netEnvCache ??=
      await resolveNetworkEnv(git, repoPath: repoPath, askpass: askpassHelper);

  /// A git-lfs transfer: the network environment, under the longer transfer
  /// ceiling instead of the ordinary network timeout.
  Future<void> _lfsNet(
    List<String> args,
    String what, {
    GitCancel? cancel,
  }) async => _ok(
    args,
    what,
    timeout: lfsTransferTimeout,
    environment: await _netEnv(),
    cancel: cancel,
  );

  /// Fetches [remote] (or every remote when null), pruning deleted refs.
  Future<void> fetch({String? remote, GitCancel? cancel}) => _net(
    ['fetch', '--prune', if (remote != null) remote else '--all'],
    'git fetch',
    cancel: cancel,
  );

  /// Pulls the current branch's upstream. [rebase] replays local commits on top
  /// instead of creating a merge; [ffOnly] refuses to reconcile a diverged
  /// history at all; [autostash] shelves and restores uncommitted work, which
  /// is what turns a pull with a dirty tree from an error into a pull.
  Future<void> pull({
    bool rebase = false,
    bool ffOnly = false,
    bool autostash = false,
    GitCancel? cancel,
  }) => _net(
    [
      'pull',
      if (rebase) '--rebase',
      if (ffOnly) '--ff-only',
      if (autostash) '--autostash',
    ],
    'git pull',
    cancel: cancel,
  );

  /// Pulls the current branch's upstream only when that is a fast-forward.
  /// `--no-rebase` beside `--ff-only` so a `pull.rebase` preference cannot
  /// turn a bulk pull into a rebase: either the branch moves forward or
  /// nothing changes.
  Future<void> pullFastForward({GitCancel? cancel}) =>
      _net(['pull', '--ff-only', '--no-rebase'], 'git pull', cancel: cancel);

  /// Makes [remote] fetch every branch again, undoing a single-branch clone.
  Future<void> fetchAllBranches(String remote) =>
      _ok(['remote', 'set-branches', remote, '*'], 'git remote set-branches');

  /// Fetches the history a shallow clone left out, turning it into a full one.
  Future<void> unshallow({GitCancel? cancel}) => _net(
    ['fetch', '--unshallow'],
    'git fetch --unshallow',
    cancel: cancel,
    timeout: _unshallowTimeout,
  );

  /// Prunes remote-tracking refs under [remote] that no longer exist upstream.
  Future<void> pruneRemote(String remote, {GitCancel? cancel}) =>
      _net(['remote', 'prune', remote], 'git remote prune', cancel: cancel);

  // --- Git LFS ---------------------------------------------------------------

  /// Downloads LFS content for the checked-out commit and replaces the
  /// pointers in the working tree with it — every object unless [include]
  /// narrows the download to files whose path matches a git-lfs pattern.
  Future<void> lfsPull({String? include, GitCancel? cancel}) => _lfsNet(
    ['lfs', 'pull', if (include != null) '--include=$include'],
    'git lfs pull',
    cancel: cancel,
  );

  /// Downloads every LFS object any ref needs, so later commands can work
  /// offline. Touches only the object store, not the working tree.
  Future<void> lfsFetchAll({GitCancel? cancel}) =>
      _lfsNet(['lfs', 'fetch', '--all'], 'git lfs fetch --all', cancel: cancel);

  /// Downloads the object [include] names at [rev] from [remote] into the
  /// object store, without touching the working tree.
  Future<void> lfsFetchObject(
    String remote,
    String rev,
    String include, {
    GitCancel? cancel,
  }) => _lfsNet(
    ['lfs', 'fetch', remote, rev, '--include=$include'],
    'git lfs fetch',
    cancel: cancel,
  );

  /// Previews what a prune would remove, without removing anything. Returned
  /// rather than thrown on failure: the caller reads the report to decide
  /// what a non-zero exit means here.
  Future<GitResult> lfsPruneDryRun({GitCancel? cancel}) async => _run(
    ['lfs', 'prune', '--dry-run', '--verbose'],
    timeout: lfsTransferTimeout,
    environment: await _netEnv(),
    cancel: cancel,
  );

  /// Removes downloaded LFS objects git-lfs judges safe to drop.
  Future<void> lfsPrune({GitCancel? cancel}) =>
      _lfsNet(['lfs', 'prune'], 'git lfs prune', cancel: cancel);

  /// Routes files matching [pattern] through LFS by adding it to
  /// `.gitattributes`. Stages nothing. The `--` here and in the other track
  /// commands keeps a pattern or path that starts with `-` from being read as
  /// an option.
  Future<void> lfsTrack(String pattern) => _ok(
    ['lfs', 'track', '--', pattern],
    'git lfs track',
    timeout: lfsLocalTimeout,
  );

  /// Routes exactly [path] through LFS; `--filename` escapes any glob
  /// characters that appear in it.
  Future<void> lfsTrackFile(String path) => _ok(
    ['lfs', 'track', '--filename', '--', path],
    'git lfs track --filename',
    timeout: lfsLocalTimeout,
  );

  /// Stops routing files matching [pattern] through LFS. git-lfs only edits
  /// the `.gitattributes` of the directory it runs in, so a pattern from a
  /// nested one runs in that [dir] (relative to the repository), written as
  /// it appears there.
  Future<void> lfsUntrack(String pattern, {String dir = ''}) async {
    final r = await git.run(
      ['lfs', 'untrack', '--', pattern],
      repoPath: dir.isEmpty ? repoPath : p.join(repoPath, dir),
      timeout: lfsLocalTimeout,
    );
    if (!r.ok) throw GitException('git lfs untrack', r);
  }

  /// Lists the patterns currently routed through LFS, as git-lfs's own
  /// report — left unparsed since callers only display it.
  Future<String> lfsTrackList() async {
    final r = await _run(['lfs', 'track'], timeout: lfsLocalTimeout);
    if (!r.ok) throw GitException('git lfs track', r);
    return r.stdout;
  }

  /// Paths a push would send: what [upstream]`...HEAD` changes, or, with no
  /// upstream or a [rev] other than HEAD, what [rev] holds that no remote has.
  /// An [upstream] that starts with `-` is never handed to git; nothing is
  /// reported for it.
  Future<List<String>> changedPathsToPush({
    String? upstream,
    String rev = 'HEAD',
  }) async {
    if (upstream != null && upstream.startsWith('-')) return const [];
    final useUpstream =
        upstream != null && upstream.isNotEmpty && rev == 'HEAD';
    final args = useUpstream
        ? ['diff', '--name-only', '-z', '$upstream...HEAD']
        : ['log', '--name-only', '-z', '--format=', rev, '--not', '--remotes'];
    final r = await _run(args);
    if (!r.ok) throw GitException('git ${args.first}', r);
    final seen = <String>{};
    for (final path in r.stdout.split('\u0000')) {
      if (path.isNotEmpty) seen.add(path);
    }
    return seen.toList();
  }

  /// Lists file locks, with which are the caller's own. Returned, never
  /// thrown on failure: a non-zero exit is how a server without locking
  /// support shows up, and the caller reads the report to tell that from
  /// other failures.
  Future<GitResult> lfsLockList({GitCancel? cancel}) async => _run(
    ['lfs', 'locks', '--verify', '--json', '--limit', '1000'],
    timeout: lfsLockTimeout,
    environment: await _netEnv(),
    cancel: cancel,
  );

  /// Locks [path] on the server and returns git-lfs's JSON report. `--`
  /// keeps a path that starts with `-` from being read as an option.
  Future<String> lfsLock(String path, {GitCancel? cancel}) async {
    if (path.isEmpty) throw ArgumentError.value(path, 'path', 'is empty');
    final r = await _run(
      ['lfs', 'lock', '--json', '--', path],
      timeout: lfsLockTimeout,
      environment: await _netEnv(),
      cancel: cancel,
    );
    if (!r.ok) throw GitException('git lfs lock', r);
    return r.stdout;
  }

  /// Releases the lock with server id [id] and returns git-lfs's JSON report.
  /// [force] releases a lock someone else holds. The id is refused when empty
  /// or dash-leading, since it would be read as an option.
  Future<String> lfsUnlock(
    String id, {
    bool force = false,
    GitCancel? cancel,
  }) async {
    if (id.isEmpty || id.startsWith('-')) {
      throw ArgumentError.value(id, 'id', 'is not a lock id');
    }
    final r = await _run(
      ['lfs', 'unlock', '--json', if (force) '--force', '--id', id],
      timeout: lfsLockTimeout,
      environment: await _netEnv(),
      cancel: cancel,
    );
    if (!r.ok) throw GitException('git lfs unlock', r);
    return r.stdout;
  }

  /// Installs git-lfs's hooks for this repository only, without touching the
  /// user's global git config.
  Future<void> lfsInstallLocal() => _ok(
    ['lfs', 'install', '--local'],
    'git lfs install --local',
    timeout: lfsLocalTimeout,
  );

  /// Re-stages [paths] through whatever filter `.gitattributes` now assigns
  /// them, so a pattern change added by [lfsTrack] takes effect on files
  /// already tracked. Stages the files' current content, edits included.
  ///
  /// Batched at 200 paths per invocation to stay clear of platform argv
  /// limits on a repository with many newly-tracked files.
  Future<void> renormalize(List<String> paths, {GitCancel? cancel}) async {
    for (var i = 0; i < paths.length; i += 200) {
      final batch = paths.sublist(i, (i + 200).clamp(0, paths.length));
      await _ok(
        ['add', '--renormalize', '--', ...batch],
        'git add --renormalize',
        timeout: lfsTransferTimeout,
        cancel: cancel,
      );
    }
  }

  /// Stages every `.gitattributes` file, at any depth, that is modified or
  /// new — the rules that make freshly staged LFS pointers pointers. Lists
  /// them first because `git add` fails outright on a pathspec that matches
  /// nothing.
  Future<void> stageGitattributes() async {
    final r = await _run([
      'ls-files',
      '-z',
      '-m',
      '-o',
      '--exclude-standard',
      '--',
      ':(glob)**/.gitattributes',
    ]);
    if (!r.ok) throw GitException('git ls-files', r);
    final paths = {
      for (final f in r.stdout.split('\x00'))
        if (f.isNotEmpty) f,
    };
    if (paths.isEmpty) return;
    await _ok(['add', '--', ...paths], 'git add');
  }

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
  /// to overwrite remote work the local ref has not seen. [remote] sends the
  /// branch to that remote rather than its upstream, and leaves the tracking
  /// configuration as it was. [tags] publishes tags alongside the branch.
  Future<void> push({
    bool force = false,
    String? remote,
    bool tags = false,
    GitCancel? cancel,
  }) async {
    final hasUpstream = (await _run([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ])).ok;
    final args = <String>['push', if (force) '--force-with-lease'];
    if (remote != null) {
      final branch = await _branchToPush();
      // Tracking is published only for a branch that has none; naming a remote
      // for a single push must not re-point an upstream that already exists.
      if (!hasUpstream) args.add('--set-upstream');
      args.addAll([remote, branch]);
    } else if (!hasUpstream) {
      final branch = await _branchToPush();
      final remotes = const LineSplitter()
          .convert((await _run(['remote'])).stdout)
          .where((s) => s.isNotEmpty)
          .toList();
      if (remotes.isEmpty) {
        throw GitException('no remote configured to push to');
      }
      final auto = remotes.contains('origin') ? 'origin' : remotes.first;
      args.addAll(['--set-upstream', auto, branch]);
    }
    if (tags) args.add('--tags');
    await _net(args, 'git push', cancel: cancel);
  }

  /// The current branch name, for a push that has to spell out its refspec.
  /// Detached HEAD has no branch to name, so it cannot be pushed this way.
  Future<String> _branchToPush() async {
    final branch = (await _run(['rev-parse', '--abbrev-ref', 'HEAD'])).out;
    if (branch == 'HEAD') {
      throw GitException('cannot push in detached HEAD state');
    }
    return branch;
  }

  // --- Merge ops ------------------------------------------------------------

  /// Merges [branch] into the current branch. Throws on conflict (the caller
  /// inspects [GitReader.conflictedFiles] to open the Merge Tool) or error.
  ///
  /// [squash] applies the other branch's work as one staged change with no
  /// commit and no second parent; git refuses to pair it with `--no-ff`, so it
  /// takes precedence. [noCommit] stops after staging the merge, leaving
  /// MERGE_HEAD set so the user's own commit is still a merge commit. [favor]
  /// picks a side for hunks both branches touched.
  Future<void> merge(
    String branch, {
    bool noFf = false,
    bool squash = false,
    bool noCommit = false,
    MergeFavor favor = MergeFavor.none,
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _traced(what: 'git merge', cancel: cancel, [
    ..._identity(authorName, authorEmail),
    'merge',
    if (squash)
      '--squash'
    else ...[
      if (noFf) '--no-ff',
      if (noCommit) '--no-commit',
    ],
    if (favor != MergeFavor.none) ...['-X', favor.name],
    branch,
  ]);

  /// Backs out a merge in progress. A conflicted `--squash` merge never wrote
  /// MERGE_HEAD, so git refuses `--abort` there; `git reset --merge` is git's
  /// own recovery for that state and leaves unrelated uncommitted work alone.
  Future<void> mergeAbort() async {
    if ((await _run(['merge', '--abort'])).ok) return;
    await _ok(['reset', '--merge'], 'git merge --abort');
  }

  /// Per-commit identity config args, prepended before a subcommand.
  static List<String> _identity(String? name, String? email) => [
    if (name != null) ...['-c', 'user.name=$name'],
    if (email != null) ...['-c', 'user.email=$email'],
  ];

  // --- Interactive rebase ---------------------------------------------------

  /// Ceiling for a rebase that runs exec steps. Each one is whatever the user
  /// typed — a full test suite, typically — so the ordinary default would kill
  /// the sequence partway through its first run.
  static const rebaseSequenceTimeout = Duration(hours: 2);

  /// Runs an interactive rebase onto [onto], driving the sequence editor with
  /// [todo] (so no terminal editor is needed). GIT_EDITOR is a no-op so squash
  /// messages auto-accept; reword is handled by exec lines in [todo]. [sign]
  /// signs every replayed commit. Throws on conflict or a failed exec (the
  /// caller inspects [GitReader.conflictedFiles]); a `break` returns normally
  /// with the rebase still in progress. [cancel] stops git, which leaves the
  /// rebase stopped on the step it was running.
  ///
  /// Exec steps and signing both wait on something of the user's — a test
  /// suite, a passphrase prompt per commit — so either earns the sequence
  /// ceiling.
  Future<void> rebase(
    String onto,
    String todo, {
    String? authorName,
    String? authorEmail,
    bool sign = false,
    GitCancel? cancel,
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
        timeout: sign || todoRunsUserExec(todo) ? rebaseSequenceTimeout : null,
        cancel: cancel,
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
  /// [sign] signs every replayed commit, which can mean a passphrase prompt
  /// per commit, so a signed rebase gets the sequence ceiling. [cancel] stops
  /// git, leaving the rebase stopped where it was.
  Future<void> rebaseOnto(
    String onto, {
    String? authorName,
    String? authorEmail,
    bool sign = false,
    GitCancel? cancel,
  }) => _ok(
    [..._identity(authorName, authorEmail), 'rebase', if (sign) '-S', onto],
    'git rebase',
    environment: {'GIT_EDITOR': 'true'},
    timeout: sign ? rebaseSequenceTimeout : null,
    cancel: cancel,
  );

  Future<void> rebaseAbort() =>
      _ok(['rebase', '--abort'], 'git rebase --abort');

  /// Drops the paused commit from the rebase sequence — the way out when the
  /// pick applied to nothing, either because the resolution left no change or
  /// because the commit already reached the base under a different sha. The
  /// rest of the sequence then runs, so it gets the same ceiling as
  /// [rebaseContinue].
  Future<void> rebaseSkip({GitCancel? cancel}) => _ok(
    ['rebase', '--skip'],
    'git rebase --skip',
    timeout: rebaseSequenceTimeout,
    cancel: cancel,
  );

  /// Continues a paused rebase after conflicts were resolved and staged. The
  /// rest of the sequence may hold exec steps, so it gets the same ceiling as
  /// the rebase that queued them.
  Future<void> rebaseContinue({
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _ok(
    [..._identity(authorName, authorEmail), 'rebase', '--continue'],
    'git rebase --continue',
    timeout: rebaseSequenceTimeout,
    cancel: cancel,
    environment: {'GIT_EDITOR': 'true'},
  );

  // --- Bisect ----------------------------------------------------------------

  /// Opens a bisect session. On its own it checks nothing out: git needs one
  /// bad and one good commit before it can begin halving the range.
  Future<void> bisectStart() => _ok(['bisect', 'start'], 'git bisect start');

  /// Records a verdict against [rev]. [term] is the repository's own word for
  /// the verdict, so bisect sessions using old/new work without translation.
  ///
  /// The revision is always named explicitly: the graph lets a verdict be
  /// assigned to a commit not currently checked out.
  Future<void> bisectMark(String term, String rev) =>
      _ok(['bisect', term, rev], 'git bisect $term');

  /// Sets [rev] (or the checked-out commit, if rev is null) aside as skipped
  /// in the bisect session.
  Future<void> bisectSkip({String? rev}) =>
      _ok(['bisect', 'skip', ?rev], 'git bisect skip');

  /// Exits the bisect session and returns to the original branch.
  Future<void> bisectReset() => _ok(['bisect', 'reset'], 'git bisect reset');

  /// The verdict trail of the session in progress: the good, bad and skip
  /// decisions git recorded, in the order they were given, as the replayable
  /// script git writes them out as.
  ///
  /// Raw stdout, unparsed — it is git's own record of how the hunt got here,
  /// where the refs only say where it currently stands.
  Future<String> bisectLog() async {
    final r = await _run(['bisect', 'log']);
    // The result travels with the exception on purpose: handlers here read
    // its stderr ahead of the message, so a message-only throw would reach
    // the user as empty text.
    if (!r.ok) throw GitException('git bisect log', r);
    return r.stdout;
  }

  /// Runs [command] over the remaining candidates until git lands on the first
  /// bad commit or gives up.
  ///
  /// Returns the result instead of throwing: the exit code and stderr together
  /// say which of several outcomes happened, and an exception would discard
  /// that. Runs under [_bisectRunTimeout] rather than the ordinary default,
  /// which a real command would blow through in the first step; [cancel] is
  /// how a run is meant to be stopped.
  Future<GitResult> bisectRun(String command, {GitCancel? cancel}) => _run(
    bisectRunArgs(command),
    timeout: _bisectRunTimeout,
    // Pinned so the outcome can be read back at all: git translates the
    // sentences that say how a run ended, and this app ships Ukrainian.
    environment: bisectRunMessageEnv,
    cancel: cancel,
  );

  // --- Branch ops -----------------------------------------------------------

  /// Creates branch [name], optionally pointing at [at] (a commit/ref).
  Future<void> createBranch(String name, {String? at}) =>
      _ok(['branch', name, ?at], 'git branch');

  /// Points the existing branch [name] at [at] without checking it out. git
  /// refuses this for a branch checked out here or in another worktree; the
  /// current one needs a reset instead.
  Future<void> forceBranch(String name, String at) =>
      _ok(['branch', '-f', name, at], 'git branch -f');

  /// Moves the current branch forward to [ref], failing rather than creating a
  /// merge commit when the two have diverged.
  Future<void> mergeFfOnly(String ref) =>
      _ok(['merge', '--ff-only', ref], 'git merge --ff-only');

  /// Checks out [ref] (a branch or commit). [ignoreOtherWorktrees] overrides
  /// git's refusal to check out a branch already held by another worktree —
  /// callers only set it after the user has confirmed the collision, since it
  /// can leave two worktrees on the same branch with one HEAD going stale.
  ///
  /// The caller picks [timeout]: in a repository using LFS, writing the files
  /// can mean downloading them.
  Future<void> checkout(
    String ref, {
    bool ignoreOtherWorktrees = false,
    Duration? timeout,
    GitCancel? cancel,
  }) => _ok(
    ['checkout', if (ignoreOtherWorktrees) '--ignore-other-worktrees', ref],
    'git checkout',
    timeout: timeout,
    cancel: cancel,
  );

  /// Creates a local branch [branch] tracking `[remote]/[branch]` and switches
  /// to it — the standard "check out a remote branch" flow. [timeout] as for
  /// [checkout].
  Future<void> checkoutTracking(
    String remote,
    String branch, {
    Duration? timeout,
    GitCancel? cancel,
  }) => _ok(
    ['switch', '-c', branch, '--track', '$remote/$branch'],
    'git switch --track',
    timeout: timeout,
    cancel: cancel,
  );

  /// Puts back what a checkout from [from] to [to] wrote before it was
  /// stopped. Each path the two differ on is restored from [from], or deleted
  /// when [from] has no such file.
  ///
  /// Touches nothing the user owns: git refuses to start a checkout that
  /// would overwrite local changes or untracked files on exactly these paths,
  /// so each of them was clean, or absent, when it began.
  Future<void> restorePartialCheckout(String from, String to) async {
    final r = await _run([
      'diff',
      '--name-status',
      '-z',
      '--no-renames',
      from,
      to,
      '--',
    ]);
    if (!r.ok) throw GitException('git diff', r);
    // `-z` pairs each status with its path: STATUS NUL PATH NUL ...
    final fields = r.stdout.split('\x00');
    final restore = <String>[];
    final added = <String>[];
    for (var i = 0; i + 1 < fields.length; i += 2) {
      (fields[i] == 'A' ? added : restore).add(fields[i + 1]);
    }
    if (restore.isNotEmpty) {
      await _ok(
        ['checkout', from, '--pathspec-from-file=-', '--pathspec-file-nul'],
        'git checkout',
        stdin: '${restore.join('\x00')}\x00',
        // The objects were checked out a moment ago, so the smudge reads
        // them locally; the ceiling only covers a store that lost them.
        timeout: lfsTransferTimeout,
      );
    }
    // git writes the index after the files, so a stop can come after it was
    // written: the new files are then staged as well as on disk.
    if (added.isNotEmpty) {
      await _ok(
        [
          'rm',
          '--cached',
          '-q',
          '--ignore-unmatch',
          '--pathspec-from-file=-',
          '--pathspec-file-nul',
        ],
        'git rm --cached',
        stdin: '${added.join('\x00')}\x00',
      );
    }
    for (final path in added) {
      try {
        final file = File(p.join(repoPath, path));
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Left behind, it shows as untracked rather than vanishing silently.
      }
    }
  }

  Future<void> renameBranch(String from, String to) =>
      _ok(['branch', '-m', from, to], 'git branch -m');

  /// Ceiling for `gc` and `maintenance run`. A full repack of a large
  /// repository takes far longer than the ordinary default; the user can
  /// cancel it sooner.
  static const housekeepingTimeout = Duration(hours: 2);

  /// Runs `git gc`. Nothing it prints is kept: with its output piped rather
  /// than on a terminal, git reports no progress at all.
  Future<void> gc({GitCancel? cancel}) =>
      _ok(['gc'], 'git gc', timeout: housekeepingTimeout, cancel: cancel);

  /// Runs `git maintenance run` with whatever tasks the repository's config
  /// enables. Silent when piped, like [gc].
  Future<void> maintenanceRun({GitCancel? cancel}) => _ok(
    ['maintenance', 'run'],
    'git maintenance run',
    timeout: housekeepingTimeout,
    cancel: cancel,
  );

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

  // --- Config ----------------------------------------------------------------

  /// Sets [key] to [value] in this repository's config, or the user's global
  /// one when [global]. `--replace-all` because a key set more than once
  /// makes a plain set refuse.
  Future<void> setConfig(String key, String value, {bool global = false}) =>
      _ok([
        'config',
        global ? '--global' : '--local',
        '--replace-all',
        key,
        value,
      ], 'git config');

  /// Removes every value of [key] from this repository's config, or the
  /// global one when [global], so the next scope down shows through. A key
  /// that is not set there (git exits 5) is already unset.
  Future<void> unsetConfig(String key, {bool global = false}) async {
    final r = await _run([
      'config',
      global ? '--global' : '--local',
      '--unset-all',
      key,
    ]);
    if (!r.ok && r.exitCode != 5) {
      throw GitException('git config --unset-all', r);
    }
  }

  // --- Tag ops --------------------------------------------------------------

  /// Creates tag [name] at [at] (default HEAD); an annotated tag when
  /// [message] is given. [sign] makes it a signed (so annotated) tag, with
  /// [signingKey] when given and git's configured key otherwise. The tagger is
  /// [authorName] / [authorEmail] when given. [cancel] stops a signer left
  /// waiting; git writes the ref only once signing is done, so a cancelled
  /// create leaves no tag behind.
  Future<void> createTag(
    String name, {
    String? at,
    String? message,
    bool sign = false,
    String? signingKey,
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _ok(
    [
      ..._identity(authorName, authorEmail),
      'tag',
      // Unsigned is said out loud: with tag.gpgSign set git would otherwise
      // sign an annotated tag unasked, and refuse a lightweight one outright.
      if (!sign)
        '--no-sign'
      else if (signingKey != null && signingKey.isNotEmpty) ...[
        '-u',
        signingKey,
      ] else
        '-s',
      if (message != null || sign) ...['-m', message ?? ''],
      name,
      ?at,
    ],
    'git tag',
    // Signing can wait on a passphrase prompt.
    timeout: sign ? hookTimeout : null,
    cancel: cancel,
  );

  /// Points tag [name] back at [object] — the tag object itself for an
  /// annotated tag, so its message and signature come back untouched. Fails
  /// rather than overwrite when [name] exists again.
  Future<void> restoreTag(String name, String object) =>
      _ok(['update-ref', 'refs/tags/$name', object, ''], 'git update-ref');

  Future<void> deleteTag(String name) => _ok(['tag', '-d', name], 'git tag -d');

  Future<void> pushTag(
    String name, {
    String remote = 'origin',
    GitCancel? cancel,
  }) => _net(['push', remote, name], 'git push tag', cancel: cancel);

  /// Deletes tag [name] on [remote]. The ref is spelled out in full because a
  /// branch and a tag can carry the same name, and the short form leaves git to
  /// guess which of the two was meant.
  Future<void> deleteRemoteTag(
    String name, {
    String remote = 'origin',
    GitCancel? cancel,
  }) => _net(
    ['push', remote, '--delete', 'refs/tags/$name'],
    'git push --delete tag',
    cancel: cancel,
  );

  // --- Notes ----------------------------------------------------------------

  /// Writes [text] as the note on [sha], replacing any note already there.
  /// Text that is empty once git tidies it removes the note instead. The
  /// notes commit is authored by [authorName] / [authorEmail] when given.
  Future<void> setNote(
    String sha,
    String text, {
    String? authorName,
    String? authorEmail,
  }) => _ok(
    [
      ..._identity(authorName, authorEmail),
      'notes',
      'add',
      '-f',
      '-F',
      '-',
      sha,
    ],
    'git notes add',
    stdin: text,
  );

  /// Removes the note on [sha]; a commit without one is left as it is.
  Future<void> removeNote(String sha) =>
      _ok(['notes', 'remove', '--ignore-missing', sha], 'git notes remove');

  /// The notes ref in use here, which no default refspec carries: sharing
  /// notes has to name it.
  Future<String> _notesRef() async {
    final r = await _run(['notes', 'get-ref']);
    if (!r.ok) throw GitException('git notes get-ref', r);
    return r.out;
  }

  /// Publishes the notes ref to [remote]. The remote's notes are merged in
  /// first, so notes someone else pushed are kept and the push is a
  /// fast-forward. False, with nothing pushed, when neither side has notes.
  Future<bool> pushNotes(
    String remote, {
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) async {
    final ref = await _notesRef();
    await _mergeRemoteNotes(remote, ref, authorName, authorEmail, cancel);
    if (!await _refExists(ref)) return false;
    await _net(['push', remote, ref], 'git push notes', cancel: cancel);
    return true;
  }

  /// Merges [remote]'s notes into the notes ref. False when the remote has no
  /// notes under that name.
  Future<bool> fetchNotes(
    String remote, {
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) async {
    final ref = await _notesRef();
    return _mergeRemoteNotes(remote, ref, authorName, authorEmail, cancel);
  }

  /// Where [remote]'s notes refs are fetched to before they are merged. Kept
  /// out of `refs/notes/` so they never pass for notes of this repository,
  /// and out of the graph's walk (see [notesWalkExcludes]).
  static String remoteNotesNamespace(String remote) =>
      'refs/mergelio/notes/$remote';

  /// Fetches [remote]'s notes aside, then merges its counterpart of [ref]
  /// into [ref]. A notes ref is a history of its own: two people's notes
  /// never fast-forward onto each other, so they are merged rather than one
  /// overwriting the other. A note both sides wrote on the same commit keeps
  /// both texts, ours first (`union`). Reports whether the remote had notes.
  Future<bool> _mergeRemoteNotes(
    String remote,
    String ref,
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  ) async {
    final aside = remoteNotesNamespace(remote);
    // Forced and pruned: the aside copy mirrors the remote, whatever it did.
    await _net(
      ['fetch', '--prune', remote, '+refs/notes/*:$aside/*'],
      'git fetch notes',
      cancel: cancel,
    );
    final theirs = '$aside/${ref.substring('refs/notes/'.length)}';
    if (!await _refExists(theirs)) return false;
    await _ok(
      [
        ..._identity(authorName, authorEmail),
        'notes',
        'merge',
        '--quiet',
        '-s',
        'union',
        theirs,
      ],
      'git notes merge',
      cancel: cancel,
    );
    return true;
  }

  Future<bool> _refExists(String ref) async =>
      (await _run(['rev-parse', '--quiet', '--verify', ref])).ok;

  // --- Commit-context ops ---------------------------------------------------

  /// Cherry-picks [sha]. A merge commit has no single diff to replay, so git
  /// demands the parent to diff it against: [mainline] is that parent's 1-based
  /// number. Give it for a merge; git rejects it on any other commit.
  Future<void> cherryPick(String sha, {int? mainline}) => _ok([
    'cherry-pick',
    if (mainline != null) ...['-m', '$mainline'],
    sha,
  ], 'git cherry-pick');

  /// Ceiling for picking several commits in one run. Each pick commits, and so
  /// runs the commit hooks, so a long batch outlasts the ordinary default.
  static const pickSequenceTimeout = Duration(minutes: 30);

  /// Cherry-picks [shas] in the order given — git keeps an explicit list's
  /// order rather than sorting it. [noCommit] applies them all to the index
  /// and working tree and leaves the committing to the user.
  Future<void> cherryPickAll(List<String> shas, {bool noCommit = false}) => _ok(
    ['cherry-pick', if (noCommit) '--no-commit', ...shas],
    'git cherry-pick',
    timeout: pickSequenceTimeout,
  );

  /// Aborts an in-progress cherry-pick, restoring the pre-pick HEAD and tree.
  Future<void> cherryPickAbort() =>
      _ok(['cherry-pick', '--abort'], 'git cherry-pick --abort');

  /// Commits a cherry-pick that paused on conflicts, once the resolution is
  /// staged. `GIT_EDITOR=true` keeps the picked message without prompting.
  Future<void> cherryPickContinue({
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _traced(
    [..._identity(authorName, authorEmail), 'cherry-pick', '--continue'],
    what: 'git cherry-pick --continue',
    environment: {'GIT_EDITOR': 'true'},
    cancel: cancel,
  );

  /// Drops the paused commit from the cherry-pick sequence — the way out when
  /// the resolution left nothing to commit. The picks after it then run, each
  /// through the commit hooks, so it gets the batch ceiling.
  Future<void> cherryPickSkip({GitCancel? cancel}) => _ok(
    ['cherry-pick', '--skip'],
    'git cherry-pick --skip',
    timeout: pickSequenceTimeout,
    cancel: cancel,
  );

  /// Reverts [sha]. As with [cherryPick], reverting a merge needs [mainline] —
  /// the 1-based parent whose side of the merge is kept.
  Future<void> revert(String sha, {int? mainline}) => _ok([
    'revert',
    '--no-edit',
    if (mainline != null) ...['-m', '$mainline'],
    sha,
  ], 'git revert');

  Future<void> revertAbort() =>
      _ok(['revert', '--abort'], 'git revert --abort');

  /// Commits a revert that paused on conflicts, once the resolution is staged.
  Future<void> revertContinue({
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _traced(
    [..._identity(authorName, authorEmail), 'revert', '--continue'],
    what: 'git revert --continue',
    environment: {'GIT_EDITOR': 'true'},
    cancel: cancel,
  );

  /// Drops the paused commit from the revert sequence (empty resolution). As
  /// with [cherryPickSkip], the reverts after it then run.
  Future<void> revertSkip({GitCancel? cancel}) => _ok(
    ['revert', '--skip'],
    'git revert --skip',
    timeout: pickSequenceTimeout,
    cancel: cancel,
  );

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

  /// Moves HEAD to [sha] and resets the index to match it, leaving the working
  /// tree alone: the changes stay on disk, unstaged.
  Future<void> resetMixed(String sha) =>
      _ok(['reset', '--mixed', sha], 'git reset --mixed');

  // --- Stash ops ------------------------------------------------------------

  /// Shelves uncommitted work as [options] describes; see [stashPushArgs].
  /// Putting the shelved files back to HEAD runs them through their filters,
  /// so the caller picks [timeout] as for [checkout].
  Future<void> stashPush([
    StashPushOptions options = const StashPushOptions(),
    Duration? timeout,
  ]) => _ok(stashPushArgs(options), 'git stash push', timeout: timeout);

  /// Creates branch [name] at the commit stash [ref] was made on, checks it
  /// out and applies the stash there, dropping it once it applies cleanly.
  Future<void> stashBranch(String name, String ref) =>
      _ok(['stash', 'branch', name, ref], 'git stash branch');

  /// Gives stash [ref] a new [message]. Git has no rename, so the same stash
  /// commit is stored again under the new message and the old entry dropped.
  ///
  /// Storing comes first: the new entry lands at `stash@{0}` and pushes the
  /// old one down by one, which is dropped only after checking it still holds
  /// the same commit. A failure part-way leaves a duplicate, never a loss. The
  /// renamed stash moves to the top of the list.
  Future<void> stashRename(String ref, String message) async {
    final index = stashIndexOf(ref);
    if (index == null) throw GitException('Not a stash entry: $ref');
    final sha = (await _run(['rev-parse', '--verify', '-q', ref])).out;
    if (sha.isEmpty) throw GitException('No such stash: $ref');
    await _ok(['stash', 'store', '-m', message, sha], 'git stash store');
    final shifted = stashRefAt(index + 1);
    final now = (await _run(['rev-parse', '--verify', '-q', shifted])).out;
    if (now != sha) {
      throw GitException('Stash list changed while renaming; kept both');
    }
    await _ok(['stash', 'drop', '-q', shifted], 'git stash drop');
  }

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

  /// Resolves a conflict by taking one whole side of it: the worktree copy is
  /// replaced with that stage of the merge. Only valid while [path] is still
  /// unmerged, and only for a side that has content there.
  Future<void> checkoutConflictSide(String path, {required bool ours}) => _ok([
    'checkout',
    ours ? '--ours' : '--theirs',
    '--',
    path,
  ], 'git checkout ${ours ? '--ours' : '--theirs'}');

  /// Resolves a conflicted submodule by recording [sha] as its gitlink.
  /// `checkout --ours/--theirs` cannot do this: it has no directory to write,
  /// and a later `git add` would record whatever the submodule happens to have
  /// checked out instead of the side that was chosen.
  ///
  /// The checkout inside the submodule is then best-effort — the chosen commit
  /// may not have been fetched there yet, which leaves the gitlink correct and
  /// the submodule's own worktree behind it.
  Future<void> setGitlink(String path, String sha) async {
    await _ok([
      'update-index',
      '--cacheinfo',
      '160000,$sha,$path',
    ], 'git update-index');
    await _run(['-C', path, 'checkout', '-q', sha]);
  }

  /// Resolves a conflict by dropping the path from the index and the worktree.
  /// `-f` because an unmerged path always looks like it has staged changes.
  Future<void> removeConflicted(String path) =>
      _ok(['rm', '-f', '-q', '--', path], 'git rm');

  Future<void> unstageFile(String path) =>
      _ok(['restore', '--staged', '--', path], 'git restore --staged');

  Future<void> stageAll() => _ok(['add', '-A'], 'git add -A');

  Future<void> unstageAll() => _ok(['reset', '-q', 'HEAD'], 'git reset');

  /// Stages exactly [paths]; deletions included.
  Future<void> stagePaths(List<String> paths) =>
      _onPaths(['add'], paths, 'git add');

  /// Unstages exactly [paths], leaving their worktree content alone.
  Future<void> unstagePaths(List<String> paths) =>
      _onPaths(['restore', '--staged'], paths, 'git restore --staged');

  /// Reverts [paths] to HEAD in both the index and the worktree. Every path
  /// must be known to git: an untracked one fails the whole command.
  Future<void> restorePathsFromHead(List<String> paths) => _onPaths(
    ['restore', '--staged', '--worktree', '--source=HEAD'],
    paths,
    'git restore',
  );

  /// Runs [command] over [paths] taken literally, so a file named `*.md` is
  /// that one file. The list goes through stdin rather than argv: a large
  /// selection would overflow a command line, Windows' first of all.
  Future<void> _onPaths(List<String> command, List<String> paths, String what) {
    if (paths.isEmpty) return Future.value();
    return _ok(
      [
        '--literal-pathspecs',
        ...command,
        '--pathspec-from-file=-',
        '--pathspec-file-nul',
      ],
      what,
      stdin: paths.map((p) => '$p\x00').join(),
    );
  }

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
  /// signature (requires the repo to be configured for it). [description]
  /// follows the summary; [trailers] and then [coauthors] (as
  /// `Co-authored-by`) form the trailer block after it. [signoff] has git add
  /// `Signed-off-by` for the committing identity. [authorName]/[authorEmail],
  /// when given, set the commit identity for this commit (the active profile).
  /// [noVerify] skips the hooks listed in [noVerifyHooks].
  /// A hook's refusal throws [HookRejectedException].
  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    bool noVerify = false,
    bool signoff = false,
    List<String> coauthors = const [],
    List<CommitTrailer> trailers = const [],
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) async {
    final message = buildCommitMessage(
      summary,
      description,
      trailers: [
        ...trailers,
        ...buildTrailers(coauthors: coauthors),
      ],
    );
    await _traced([
      // Per-commit identity via -c, applied before the subcommand.
      if (authorName != null) ...['-c', 'user.name=$authorName'],
      if (authorEmail != null) ...['-c', 'user.email=$authorEmail'],
      'commit',
      if (amend) '--amend',
      if (sign) '-S',
      if (noVerify) '--no-verify',
      // git appends Signed-off-by to the trailer block itself, from the
      // committing identity set above.
      if (signoff) '--signoff',
      '-m',
      message,
    ], cancel: cancel);
  }

  /// Runs a git command that may run hooks and, when one refuses it, throws
  /// [HookRejectedException] naming the hook. Git prints little or nothing of
  /// its own in that case — the transcript is the hook's — so the hook is read
  /// from the trace git writes as it runs children. Hooks are the user's own
  /// programs, so the command runs under [timeout] rather than the ordinary
  /// default.
  Future<void> _traced(
    List<String> args, {
    String what = 'git commit',
    Map<String, String>? environment,
    Duration timeout = hookTimeout,
    GitCancel? cancel,
  }) async {
    final dir = _privateTempDir();
    // Without a private place for the trace the command still runs; it only
    // loses the hook's name if one refuses.
    final trace = dir == null ? null : File(p.join(dir.path, 'trace2.json'));
    try {
      final r = await _run(
        [
          // A hook skipped for lacking its execute bit otherwise adds a hint
          // to whatever the hook that did run printed.
          '-c',
          'advice.ignoredHook=false',
          ...args,
        ],
        environment: {
          ...?environment,
          if (trace != null) 'GIT_TRACE2_EVENT': trace.path,
        },
        timeout: timeout,
        cancel: cancel,
      );
      if (r.ok) return;
      final hook = trace != null && await trace.exists()
          ? rejectingHook(await trace.readAsString())
          : null;
      if (hook != null) throw HookRejectedException(hook, r);
      throw GitException(what, r);
    } finally {
      try {
        dir?.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort: a leaked temp file is not worth failing the op over.
      }
    }
  }

  /// A new temp directory only this user can read, for the trace, which
  /// carries the whole command line, message included. Null when one cannot
  /// be had.
  ///
  /// Dart creates temp directories 0700 on macOS but with the umask on Linux
  /// — 0755 — where /tmp is shared, so the mode is set here rather than
  /// trusted. Windows keeps %TEMP% inside the user's own profile. Everything
  /// is synchronous: the commit must not wait on the event loop before git
  /// starts.
  static Directory? _privateTempDir() {
    final Directory dir;
    try {
      dir = Directory.systemTemp.createTempSync('mergelio_commit_');
    } on FileSystemException {
      return null;
    }
    if (Platform.isWindows) return dir;
    try {
      if (Process.runSync('chmod', ['700', dir.path]).exitCode == 0) {
        return dir;
      }
    } on ProcessException {
      // No chmod to run: treat it as a directory that cannot be made private.
    }
    try {
      dir.deleteSync();
    } on FileSystemException {
      // Empty and about to be abandoned either way.
    }
    return null;
  }

  /// Rewrites the message of HEAD, leaving its tree alone. `--only` with no
  /// paths is git's way of amending the last commit *without* folding in
  /// whatever is already staged — a plain `--amend` would absorb it silently.
  /// Hooks run as for any commit; [noVerify] skips those it can, and a refusal
  /// throws [HookRejectedException].
  Future<void> amendMessage(
    String summary, {
    String description = '',
    bool sign = false,
    bool noVerify = false,
    String? authorName,
    String? authorEmail,
    GitCancel? cancel,
  }) => _traced(cancel: cancel, [
    ..._identity(authorName, authorEmail),
    'commit',
    '--amend',
    '--only',
    if (sign) '-S',
    if (noVerify) '--no-verify',
    '-m',
    joinCommitMessage(summary, description),
  ]);

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

  /// Runs `git apply` with [flags] over [patch], kept as bytes so a patch to
  /// a file in another encoding reaches git unchanged.
  Future<GitResult> _applyPatchBytes(
    List<int> patch,
    List<String> flags,
  ) async {
    final dir = await Directory.systemTemp.createTemp('mergelio_patch_');
    final tmp = File('${dir.path}/apply.patch');
    try {
      await tmp.writeAsBytes(patch);
      // A 3-way run says it left conflicts only in its message, which is
      // read, so the message must not come back translated.
      return await _run(
        ['apply', ...flags, tmp.path],
        environment: bisectRunMessageEnv,
        timeout: patchApplyTimeout,
      );
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
        if (await dir.exists()) await dir.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }

  /// The files [patch] touches, as `git apply --numstat -z` prints them.
  Future<String> patchNumstat(List<int> patch) async {
    final r = await _applyPatchBytes(patch, ['--numstat', '-z']);
    if (!r.ok) throw GitException('git apply --numstat failed', r);
    return r.stdout;
  }

  /// A dry run of [applyPatch]: nothing is written.
  Future<GitResult> checkPatch(
    List<int> patch, {
    bool index = false,
    bool threeWay = false,
  }) => _applyPatchBytes(patch, [
    '--check',
    if (index) '--index',
    if (threeWay) '--3way',
  ]);

  /// Applies [patch] to the working tree, also to the index when [index] is
  /// set. [threeWay] merges where a hunk does not fit and leaves conflicts.
  Future<void> applyPatch(
    List<int> patch, {
    bool index = false,
    bool threeWay = false,
    bool reverse = false,
  }) async {
    final r = await _applyPatchBytes(patch, [
      if (index) '--index',
      if (threeWay) '--3way',
      if (reverse) '--reverse',
    ]);
    if (!r.ok) throw GitException('git apply failed', r);
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

  /// The commits [head] has over [base] as one mbox of patches, oldest first —
  /// what `git am` takes back in. Leaves the repository untouched.
  Future<String> formatPatch(String base, String head) async {
    final r = await _run([
      'format-patch',
      '--stdout',
      '--no-color',
      '$base..$head',
    ]);
    if (!r.ok) throw GitException('git format-patch failed', r);
    return r.stdout;
  }

  /// [formatPatch], written as one numbered file per commit into [dir].
  /// Returns the paths git wrote, in order.
  Future<List<String>> formatPatchToDir(
    String base,
    String head,
    String dir,
  ) async {
    final r = await _run(['format-patch', '-o', dir, '$base..$head']);
    if (!r.ok) throw GitException('git format-patch failed', r);
    return [
      for (final line in const LineSplitter().convert(r.stdout))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }
}
