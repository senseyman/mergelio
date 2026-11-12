import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'git_network_overrides.dart';
import 'git_service.dart';

/// Configuration laid over every git command that talks to a remote. None
/// here; the app supplies its proxy setting from above the domain layer.
final gitNetworkOverridesProvider = Provider<GitNetworkOverrides>(
  (_) => GitNetworkOverrides.none,
);

/// The active Git engine. Swappable (system git now; libgit2 reads later).
///
/// The overrides are read per command rather than watched: everything that
/// talks to git holds this service, and a proxy change must not rebuild it.
final gitServiceProvider = Provider<GitService>(
  (ref) => NetworkEnvGitService(
    const SystemGitService(),
    () => ref.read(gitNetworkOverridesProvider),
  ),
);

/// The git's `--version` answer, asked once per session: the binary does not
/// change under a running app, and lookups that branch on it happen for every
/// commit or comparison opened.
final gitVersionProvider = FutureProvider<String>(
  (ref) => ref.watch(gitServiceProvider).version(),
);
