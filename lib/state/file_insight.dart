import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/blame.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/models.dart';

typedef FileKey = ({String repo, String path});

/// Commit history of a file, following renames.
final fileHistoryProvider = FutureProvider.family
    .autoDispose<List<Commit>, FileKey>(
      (ref, key) => GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).fileHistory(key.path),
    );

/// Per-line blame of a file.
final blameProvider = FutureProvider.family
    .autoDispose<List<BlameLine>, FileKey>((ref, key) async {
      final raw = await GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).blame(key.path);
      return parseBlame(raw);
    });
