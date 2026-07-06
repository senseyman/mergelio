import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'git_service.dart';

/// The active Git engine. Swappable (system git now; libgit2 reads later).
final gitServiceProvider = Provider<GitService>(
  (_) => const SystemGitService(),
);
