import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
    @Default([]) List<String> tags,
    @Default([]) List<Stash> stashes,
    @Default([]) List<WorkingFile> working,
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

final repoDataProvider = FutureProvider.family<RepoData, String>((
  ref,
  path,
) async {
  final reader = GitReader(ref.watch(gitServiceProvider), path);
  final results = await Future.wait([
    // Interim cap; lift once the graph gets windowed rendering.
    reader.commits(maxCount: 5000),
    reader.branches(),
    reader.remotes(),
    reader.tags(),
    reader.stashes(),
    reader.status(),
  ]);
  final commits = assignLanes(results[0] as List<Commit>);
  final branches = assignBranchColors(results[1] as List<Branch>, commits);
  final current = branches.where((b) => b.current);
  final squash = current.isEmpty
      ? const <SquashLink>[]
      : await reader.squashLinks(branches, into: current.first.name);
  return RepoData(
    commits: commits,
    branches: branches,
    remotes: results[2] as List<String>,
    tags: results[3] as List<String>,
    stashes: results[4] as List<Stash>,
    working: results[5] as List<WorkingFile>,
    squashLinks: squash,
  );
});
