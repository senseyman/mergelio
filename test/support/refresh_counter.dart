import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Answers every git call with empty output.
class SilentGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Repository actions that count the reloads asked of them instead of
/// re-reading anything.
class _CountingActions extends RepoActions {
  final Map<String, int> counts;
  _CountingActions(Ref ref, String path, this.counts)
    : super(ref, path, GitWriter(SilentGit(), path));

  @override
  void refresh() => counts[path] = (counts[path] ?? 0) + 1;
}

/// Overrides [repoActionsProvider] so each reload asked of a repository adds
/// one to [counts] under its path.
Override countRefreshes(Map<String, int> counts) => repoActionsProvider
    .overrideWith((ref, path) => _CountingActions(ref, path, counts));
