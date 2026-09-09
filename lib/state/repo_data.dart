import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/lane_layout.dart';
import '../domain/git/models.dart';

part 'repo_data.freezed.dart';

/// Everything read from an open repository: refs, commit graph (lanes already
/// assigned) and working-tree state. All UI panels derive from this.
@freezed
class RepoData with _$RepoData {
  const factory RepoData({
    @Default([]) List<Commit> commits,
    @Default([]) List<Branch> branches,
    @Default([]) List<String> remotes,
    @Default([]) List<RemoteBranch> remoteBranches,
    @Default([]) List<String> tags,
    @Default([]) List<Stash> stashes,
    @Default([]) List<WorkingFile> working,
    @Default([]) List<Submodule> submodules,
    // Inferred squash-merge connectors (no git parent edge exists).
    @Default([]) List<SquashLink> squashLinks,
    // The walk filled the page it asked for, so older commits exist beyond
    // [commits]. Raise [commitLimitProvider] to bring them in.
    @Default(false) bool hasMoreCommits,
  }) = _RepoData;
}

/// Loads [RepoData] for the repository at `path`. The cheap ref, index and
/// working-tree reads run in parallel and decide whether the history walk has
/// to run at all; the commit list gets lane layout applied before it lands in
/// state. `ref.refresh` / `ref.invalidate` re-reads after a mutating op.
/// Files changed by one commit, for the details panel.
final commitFilesProvider = FutureProvider.family
    .autoDispose<List<CommitFileChange>, ({String repo, String sha})>((
      ref,
      key,
    ) async {
      final reader = GitReader(ref.watch(gitServiceProvider), key.repo);
      return reader.commitFiles(key.sha);
    });

/// Signature verification for the one commit shown in the details panel.
/// On demand because verifying spawns gpg per signed commit — doing it for
/// the whole graph takes seconds on a repository that enforces signing.
final commitSignatureProvider = FutureProvider.family
    .autoDispose<String, ({String repo, String sha})>((ref, key) async {
      final reader = GitReader(ref.watch(gitServiceProvider), key.repo);
      return reader.signatureStatus(key.sha);
    });

/// Per-repo cache of the last squash-link inference, keyed by branch tips.
final _squashCache = <String, ({String sig, List<SquashLink> links})>{};

/// Commits loaded on open. The graph extends the limit when the user scrolls
/// to the end, so the cost of opening a monorepo no longer scales with its
/// history.
const commitPageSize = 2000;

/// How much history the graph currently wants for the repository at `path`.
/// Deliberately outside [repoDataProvider] so it survives the invalidations the
/// watcher fires: a refresh keeps whatever the user has paged in.
final commitLimitProvider = StateProvider.family<int, String>(
  (ref, path) => commitPageSize,
);

/// Repositories whose history stays cached. An entry is a whole loaded page of
/// commits, so unlike the squash-link cache this one has to be bounded: a long
/// session that visits many repositories would otherwise pin them all.
const commitCacheLimit = 4;

/// Per-repo cache of the last history walk, keyed by the refs it walked and the
/// page size it walked them with. Commits are stored after [assignLanes] so a
/// hit skips the layout pass as well as the walk. Insertion-ordered, and reads
/// re-insert, which makes eviction of the first key least-recently-used.
final _commitCache =
    <String, ({String sig, List<Commit> commits, bool more})>{};

void _cacheCommits(
  String path,
  ({String sig, List<Commit> commits, bool more}) entry,
) {
  _commitCache.remove(path);
  _commitCache[path] = entry;
  while (_commitCache.length > commitCacheLimit) {
    _commitCache.remove(_commitCache.keys.first);
  }
}

final repoDataProvider = FutureProvider.family<RepoData, String>(
  name: 'repoData',
  (ref, path) => appLog.timed('Load repo', () async {
    final reader = GitReader(ref.watch(gitServiceProvider), path);
    final limit = ref.watch(commitLimitProvider(path));
    final started = DateTime.now();
    // Refs, index and working tree first: all cheap, and the ref signature
    // decides whether the expensive history walk below has to run at all.
    final results = await Future.wait([
      reader.branches(),
      reader.remotes(),
      reader.tags(),
      reader.stashes(),
      reader.status(),
      reader.remoteBranches(),
      reader.submodules(),
      reader.refSignature(),
    ]);
    final refsDone = DateTime.now();
    final stashes = results[3] as List<Stash>;
    // The walk starts from every ref plus the stash entries, and returns a
    // different list when the page size changes, so both belong in the key.
    final commitSig = [
      results[7] as String,
      for (final s in stashes) s.sha,
      'limit=$limit',
    ].join('\n');
    final cachedCommits = _commitCache[path];
    final List<Commit> commits;
    final bool hasMore;
    var walked = false;
    if (cachedCommits != null && cachedCommits.sig == commitSig) {
      commits = cachedCommits.commits;
      hasMore = cachedCommits.more;
      _cacheCommits(path, cachedCommits); // freshen: this repo is in use
    } else {
      walked = true;
      final page = await reader.commitPage(maxCount: limit);
      commits = assignLanes(page.commits);
      hasMore = page.truncated;
      _cacheCommits(path, (sig: commitSig, commits: commits, more: hasMore));
    }
    final walkDone = DateTime.now();
    final branches = assignBranchColors(results[0] as List<Branch>, commits);
    final current = branches.where((b) => b.current);
    // Squash-link inference spawns ~5 git subprocesses per branch — very heavy.
    // Cache it per repo, keyed by the branch tips + current branch, so a
    // working-tree-only refresh (tips unchanged) reuses the result instead of
    // re-running the whole storm.
    final List<SquashLink> squash;
    if (current.isEmpty) {
      squash = const [];
    } else {
      final sig = [
        current.first.name,
        for (final b in branches) '${b.name}@${b.tip}',
      ].join(',');
      final cached = _squashCache[path];
      if (cached != null && cached.sig == sig) {
        squash = cached.links;
      } else {
        squash = await reader.squashLinks(branches, into: current.first.name);
        _squashCache[path] = (sig: sig, links: squash);
      }
    }
    // Phase breakdown so a slow open points at its cause: ref reads, the
    // history walk plus lane layout (both scale with commit count) or
    // squash-link inference. A refresh that hits either cache says so.
    final squashDone = DateTime.now();
    int ms(DateTime from, DateTime to) => to.difference(from).inMilliseconds;
    appLog.info(
      'Load repo phases: ${commits.length} commits — '
      'ref reads ${ms(started, refsDone)}ms, '
      'history ${ms(refsDone, walkDone)}ms${walked ? '' : ' (cached)'}, '
      'squash links ${ms(walkDone, squashDone)}ms',
      scope: path,
    );
    return RepoData(
      commits: commits,
      branches: branches,
      remotes: results[1] as List<String>,
      tags: results[2] as List<String>,
      stashes: stashes,
      working: results[4] as List<WorkingFile>,
      remoteBranches: results[5] as List<RemoteBranch>,
      submodules: results[6] as List<Submodule>,
      squashLinks: squash,
      hasMoreCommits: hasMore,
    );
  }, scope: path),
);
