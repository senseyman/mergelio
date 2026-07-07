import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_writer.dart';
import 'repo_data.dart';

/// Mutating git operations for one repo, each followed by a refresh of
/// [repoDataProvider] so the graph, counts and file lists update in lockstep.
class RepoActions {
  final Ref _ref;
  final String path;
  final GitWriter _writer;
  RepoActions(this._ref, this.path, this._writer);

  void _refresh() => _ref.invalidate(repoDataProvider(path));

  Future<void> stageFile(String p) async {
    await _writer.stageFile(p);
    _refresh();
  }

  Future<void> unstageFile(String p) async {
    await _writer.unstageFile(p);
    _refresh();
  }

  Future<void> stageAll() async {
    await _writer.stageAll();
    _refresh();
  }

  Future<void> unstageAll() async {
    await _writer.unstageAll();
    _refresh();
  }

  Future<void> applyPatch(String patch, {bool reverse = false}) async {
    await _writer.applyToIndex(patch, reverse: reverse);
    _refresh();
  }

  Future<void> commit(
    String summary, {
    String description = '',
    bool amend = false,
    bool sign = false,
    List<String> coauthors = const [],
  }) async {
    await _writer.commit(
      summary,
      description: description,
      amend: amend,
      sign: sign,
      coauthors: coauthors,
    );
    _refresh();
  }
}

final repoActionsProvider = Provider.family<RepoActions, String>(
  (ref, path) =>
      RepoActions(ref, path, GitWriter(ref.watch(gitServiceProvider), path)),
);
