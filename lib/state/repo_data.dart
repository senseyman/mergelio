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
  }) = _RepoData;
}

/// Loads [RepoData] for the repository at `path`. Reads run in parallel; the
/// commit list gets lane layout applied before it lands in state. `ref.refresh`
/// / `ref.invalidate` re-reads after a mutating op.
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

final repoDataProvider = FutureProvider.family<RepoData, String>(
  name: 'repoData',
  (ref, path) => appLog.timed('Load repo', () async {
    final reader = GitReader(ref.watch(gitServiceProvider), path);
    final started = DateTime.now();
    final results = await Future.wait([
      // Load up to the §12 target of 50k commits — the list is virtualised and
      // lane layout / search stay within budget at that size (perf_benchmark).
      // The cap still bounds pathological monorepos.
      reader.commits(maxCount: 50000),
      reader.branches(),
      reader.remotes(),
      reader.tags(),
      reader.stashes(),
      reader.status(),
      reader.remoteBranches(),
      reader.submodules(),
    ]);
    final readsDone = DateTime.now();
    final commits = assignLanes(results[0] as List<Commit>);
    final branches = assignBranchColors(results[1] as List<Branch>, commits);
    final layoutDone = DateTime.now();
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
    // Phase breakdown so a slow open points at its cause: git reads, lane
    // layout (CPU, scales with commit count) or squash-link inference.
    final squashDone = DateTime.now();
    int ms(DateTime from, DateTime to) => to.difference(from).inMilliseconds;
    appLog.info(
      'Load repo phases: ${commits.length} commits — '
      'git reads ${ms(started, readsDone)}ms, '
      'lane layout ${ms(readsDone, layoutDone)}ms, '
      'squash links ${ms(layoutDone, squashDone)}ms',
      scope: path,
    );
    return RepoData(
      commits: commits,
      branches: branches,
      remotes: results[2] as List<String>,
      tags: results[3] as List<String>,
      stashes: results[4] as List<Stash>,
      working: results[5] as List<WorkingFile>,
      remoteBranches: results[6] as List<RemoteBranch>,
      submodules: results[7] as List<Submodule>,
      squashLinks: squash,
    );
  }, scope: path),
);
