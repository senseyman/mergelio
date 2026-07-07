import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel for selecting the WIP (uncommitted changes) row in the graph.
const wipSelection = 'WIP';

/// Sha of the selected graph row, [wipSelection] for the WIP node, or null
/// when nothing is selected. The details panel derives from this.
final selectedCommitProvider = StateProvider<String?>((_) => null);
