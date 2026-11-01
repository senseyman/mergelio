import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query narrowing the sidebar's Branches section, per repository. Kept
/// for the session so switching tabs and back does not lose it.
final branchFilterProvider = StateProvider.family<String, String>(
  (ref, path) => '',
);
