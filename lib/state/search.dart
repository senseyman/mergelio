import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/search.dart';

/// Active global-search query, or null when the search bar is closed. Driving
/// the graph's dim/highlight and the result navigation.
final searchQueryProvider = StateProvider<CommitQuery?>((_) => null);
