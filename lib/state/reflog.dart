import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/reflog.dart';

/// How much of the reflog one read fetches. A read that comes back with this
/// many entries has probably been cut short, which the section says out loud.
const reflogPageSize = 200;

/// How many entries a reflog needs before the section offers a filter. Below
/// this the list is short enough to read, and the field is just clutter.
const reflogFilterThreshold = 20;

/// The filter text for one repository's reflog section. Auto-disposing means
/// collapsing the section clears the filter, so reopening it never hides
/// entries behind a query the user has forgotten typing.
final reflogFilterProvider = StateProvider.autoDispose.family<String, String>(
  (ref, path) => '',
);

/// HEAD's reflog for the repository at `path`.
///
/// Deliberately its own provider rather than a field of `RepoData`: those
/// reads all run again on every refresh, and the reflog is only worth a
/// subprocess while someone has the section open. Auto-disposing drops it
/// again when they collapse it.
final reflogProvider = FutureProvider.family
    .autoDispose<List<ReflogEntry>, String>(
      (ref, path) => GitReader(
        ref.watch(gitServiceProvider),
        path,
      ).reflog(maxCount: reflogPageSize),
    );
