import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/bisect.dart';
import 'repo_actions.dart';
import 'repo_data.dart';

/// The bisect the repository is in the middle of, re-read on every refresh.
///
/// Watching the repository data is what keeps the bar in step with the graph:
/// every bisect action ends in a refresh, and that refresh is what invalidates
/// this. Invalidating it directly from the action layer would fetch even with
/// nothing listening.
final bisectStateProvider = FutureProvider.family<BisectState?, String>((
  ref,
  path,
) {
  ref.watch(repoDataProvider(path));
  return ref.read(repoActionsProvider(path)).bisectState();
});
