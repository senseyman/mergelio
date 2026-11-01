import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query narrowing the sidebar's Branches section, per repository. Kept
/// for the session so switching tabs and back does not lose it.
final branchFilterProvider = StateProvider.family<String, String>(
  (ref, path) => '',
);

/// Whether the Branches filter box is showing in the section header, per
/// repository. Closing it clears [branchFilterProvider] as well.
final branchFilterOpenProvider = StateProvider.family<bool, String>(
  (ref, path) => false,
);
