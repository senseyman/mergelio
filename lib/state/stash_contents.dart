import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/stash.dart';

/// Which stash of which repository to read. A stash commit never changes, so
/// its sha alone keys the contents.
typedef StashKey = ({String repoPath, String sha});

/// What a stash holds, read without applying it.
final stashContentsProvider = FutureProvider.family
    .autoDispose<StashContents, StashKey>(
      (ref, key) => GitReader(
        ref.watch(gitServiceProvider),
        key.repoPath,
      ).stashContents(key.sha),
    );
