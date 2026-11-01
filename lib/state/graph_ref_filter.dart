import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/graph_ref_filter.dart';
import 'operation_journal.dart' show kvStoreProvider;

/// The branches hidden from, or soloed in, the commit graph of the repository
/// at `path`. Kept in the app's key-value store, so it outlives a restart.
final graphRefFilterProvider =
    AsyncNotifierProvider.family<
      GraphRefFilterController,
      GraphRefFilter,
      String
    >(GraphRefFilterController.new);

class GraphRefFilterController
    extends FamilyAsyncNotifier<GraphRefFilter, String> {
  String get _key => 'graphRefs:$arg';

  @override
  Future<GraphRefFilter> build(String path) async {
    final raw = await ref.read(kvStoreProvider).get(_key);
    return raw == null ? GraphRefFilter.none : GraphRefFilter.fromJson(raw);
  }

  Future<void> toggleHidden(String ref) => _update((f) => f.toggleHidden(ref));

  Future<void> toggleSolo(String ref) => _update((f) => f.toggleSolo(ref));

  /// Shows every branch again.
  Future<void> clear() => _update((_) => GraphRefFilter.none);

  // The last update queued. Each one reads the state the previous left, so
  // two taps in quick succession both apply instead of the later overwriting
  // the earlier from the same starting value.
  Future<void> _updates = Future.value();

  Future<void> _update(GraphRefFilter Function(GraphRefFilter) change) {
    final run = _updates.then((_) async {
      final next = change(await future);
      // Shown first: the graph follows at once, and a failed save below costs
      // only the restart, not the change.
      state = AsyncData(next);
      try {
        await ref.read(kvStoreProvider).put(_key, next.toJson());
      } on Object catch (e) {
        appLog.warn('Saving the graph branch filter failed: $e', scope: arg);
      }
    });
    _updates = run;
    return run;
  }
}
