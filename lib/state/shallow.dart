import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'maintenance.dart';

/// Whether the repository at the path is a shallow clone. Re-read when the
/// refs move, which a fetch done outside the app does too; a deepening fetch
/// that moves no ref is followed by whoever ran it invalidating this.
final shallowRepoProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  path,
) {
  ref.watch(maintenanceRefsKeyProvider(path));
  return GitReader(ref.watch(gitServiceProvider), path).isShallow();
});
