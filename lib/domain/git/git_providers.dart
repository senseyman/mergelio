import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'git_service.dart';

/// The active Git engine. Swappable (system git now; libgit2 reads later).
final gitServiceProvider = Provider<GitService>(
  (_) => const SystemGitService(),
);

/// The git's `--version` answer, asked once per session: the binary does not
/// change under a running app, and lookups that branch on it happen for every
/// commit or comparison opened.
final gitVersionProvider = FutureProvider<String>(
  (ref) => ref.watch(gitServiceProvider).version(),
);
