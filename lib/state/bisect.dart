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

/// Telling "git says there is no bisect" apart from "nobody could ask git".
///
/// `valueOrNull` collapses those two into the same null, and acting on that
/// null is how an unreachable git turns into a menu offering `git bisect
/// start` in the middle of a hunt — a command that throws every bisect ref
/// away and exits 0, losing a search nobody can get back.
extension BisectRead on AsyncValue<BisectState?> {
  /// True while the answer is not in: the read failed, or it has not landed
  /// yet. A refresh over an earlier answer does not count — git has already
  /// said what the repository is doing and is only being asked again.
  bool get unknown => hasError || !hasValue;

  /// The bisect git reported, and null when it reported none. Also null while
  /// [unknown], so the two are read together: a null on its own says nothing.
  BisectState? get bisect => unknown ? null : valueOrNull;
}
