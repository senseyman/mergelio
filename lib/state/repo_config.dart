import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/repo_config.dart';

/// The git config keys the Repository preferences edit, in every scope. Read
/// when the tab is shown; whoever writes a key invalidates it so the rows show
/// what git reports next.
final repoConfigProvider = FutureProvider.family
    .autoDispose<RepoConfig, String>((ref, repo) async {
      return GitReader(ref.watch(gitServiceProvider), repo).repoConfig();
    });
