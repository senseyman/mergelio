/// An operation a repository sits in the middle of, as git's own state files
/// show it.
enum RepoOp { merge, rebase, am, cherryPick, revert, bisect }

/// Why a repository is left out of a bulk fast-forward pull. Declared in the
/// order [pullSkipReason] checks them: the first that applies is the one
/// reported.
enum PullSkip {
  unreadable,
  operation,
  detached,
  noUpstream,
  upstreamGone,
  dirty,
  diverged,
  upToDate,
}

/// The branch and working-tree half of a repository's state, read from one
/// `git status --porcelain=v2 --branch -z`.
class StatusSummary {
  /// Checked-out branch, null when HEAD is detached (or git said nothing).
  final String? branch;
  final bool detached;

  /// The branch has no commit yet.
  final bool unborn;

  /// Tracking ref, e.g. `origin/main`; null when the branch tracks nothing.
  final String? upstream;

  /// A tracking ref is configured but no longer exists — deleted on the
  /// remote and pruned by a fetch.
  final bool upstreamGone;
  final int ahead;
  final int behind;

  /// Tracked paths with staged or unstaged changes, conflicts excluded.
  final int changed;
  final int conflicted;
  final int untracked;

  const StatusSummary({
    this.branch,
    this.detached = false,
    this.unborn = false,
    this.upstream,
    this.upstreamGone = false,
    this.ahead = 0,
    this.behind = 0,
    this.changed = 0,
    this.conflicted = 0,
    this.untracked = 0,
  });
}

/// Everything the dashboard shows for one repository.
class RepoSnapshot {
  final StatusSummary summary;
  final int stashCount;
  final RepoOp? op;

  /// When the repository last fetched, from FETCH_HEAD; null if it never has.
  final DateTime? lastFetch;

  const RepoSnapshot({
    required this.summary,
    required this.stashCount,
    this.op,
    this.lastFetch,
  });
}

/// Parses `git status --porcelain=v2 --branch -z`. Header lines carry the
/// branch; entry records are only counted. Unknown or truncated records are
/// skipped rather than failing the whole summary.
StatusSummary parseStatusSummary(String out) {
  String? branch;
  var detached = false;
  var unborn = false;
  String? upstream;
  var sawAb = false;
  var ahead = 0;
  var behind = 0;
  var changed = 0;
  var conflicted = 0;
  var untracked = 0;

  final records = out.split('\x00');
  var i = 0;
  while (i < records.length) {
    final r = records[i];
    i++;
    if (r.isEmpty) continue;
    if (r.startsWith('# ')) {
      final space = r.indexOf(' ', 2);
      if (space == -1) continue;
      final key = r.substring(2, space);
      final value = r.substring(space + 1);
      switch (key) {
        case 'branch.oid':
          unborn = value == '(initial)';
        case 'branch.head':
          if (value == '(detached)') {
            detached = true;
          } else {
            branch = value;
          }
        case 'branch.upstream':
          upstream = value;
        case 'branch.ab':
          sawAb = true;
          for (final part in value.split(' ')) {
            final plus = part.startsWith('+');
            if (!plus && !part.startsWith('-')) continue;
            final n = int.tryParse(part.substring(1)) ?? 0;
            if (plus) {
              ahead = n;
            } else {
              behind = n;
            }
          }
      }
      continue;
    }
    switch (r[0]) {
      case '1':
        changed++;
      case '2':
        changed++;
        // A rename or copy is followed by its original path.
        i++;
      case 'u':
        conflicted++;
      case '?':
        untracked++;
    }
  }

  return StatusSummary(
    branch: branch,
    detached: detached,
    unborn: unborn,
    upstream: upstream,
    // Git prints `branch.ab` whenever the upstream resolves, so an upstream
    // without one names a ref that is gone.
    upstreamGone: upstream != null && !sawAb,
    ahead: ahead,
    behind: behind,
    changed: changed,
    conflicted: conflicted,
    untracked: untracked,
  );
}

/// The state files the dashboard asks git to locate, as `--git-path` names.
const dashboardStateFiles = [
  'MERGE_HEAD',
  'rebase-merge',
  'rebase-apply',
  'rebase-apply/applying',
  'CHERRY_PICK_HEAD',
  'REVERT_HEAD',
  'BISECT_LOG',
];

/// The operation implied by which of [dashboardStateFiles] exist. A rebase is
/// checked first: it replays picks, and git can leave CHERRY_PICK_HEAD beside
/// it while one is conflicted. A bisect comes last, since a merge or pick
/// paused inside it is what the user has to deal with first.
RepoOp? opFromStateFiles(Set<String> present) {
  if (present.contains('rebase-merge')) return RepoOp.rebase;
  if (present.contains('rebase-apply')) {
    return present.contains('rebase-apply/applying')
        ? RepoOp.am
        : RepoOp.rebase;
  }
  if (present.contains('MERGE_HEAD')) return RepoOp.merge;
  if (present.contains('CHERRY_PICK_HEAD')) return RepoOp.cherryPick;
  if (present.contains('REVERT_HEAD')) return RepoOp.revert;
  if (present.contains('BISECT_LOG')) return RepoOp.bisect;
  return null;
}

/// Entries in a reflog file — for `logs/refs/stash`, the stash count.
int countReflogEntries(String text) =>
    text.split('\n').where((l) => l.trim().isNotEmpty).length;

/// Why [s] cannot take a bulk fast-forward pull, or null when it can: on a
/// branch, tracking an upstream that exists, behind it and not ahead, with
/// no tracked change and no operation in progress. Untracked files do not
/// count — `--ff-only` refuses on its own if one would be overwritten.
PullSkip? pullSkipReason(RepoSnapshot? s) {
  if (s == null) return PullSkip.unreadable;
  final m = s.summary;
  if (s.op != null) return PullSkip.operation;
  if (m.detached || m.branch == null) return PullSkip.detached;
  if (m.upstream == null) return PullSkip.noUpstream;
  if (m.upstreamGone) return PullSkip.upstreamGone;
  if (m.changed > 0 || m.conflicted > 0) return PullSkip.dirty;
  if (m.ahead > 0 && m.behind > 0) return PullSkip.diverged;
  if (m.behind == 0) return PullSkip.upToDate;
  return null;
}
