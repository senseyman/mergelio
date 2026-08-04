import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asked before something takes an editor away: leaving Files mode, closing a
/// repository tab, quitting. Each open editor pane registers a guard for its
/// repository while it is mounted; a repository with nothing mounted has
/// nothing unsaved to lose, so it answers yes.
///
/// A guard returns false when the user backed out, which cancels whatever was
/// about to happen.
class UnsavedGuards {
  final _guards = <String, Future<bool> Function()>{};

  void register(String repoPath, Future<bool> Function() guard) =>
      _guards[repoPath] = guard;

  void unregister(String repoPath) => _guards.remove(repoPath);

  Future<bool> confirm(String repoPath) async =>
      await _guards[repoPath]?.call() ?? true;

  /// Asks every repository, stopping at the first refusal so the user is not
  /// walked through prompts for a quit they have already cancelled.
  Future<bool> confirmAll() async {
    for (final guard in [..._guards.values]) {
      if (!await guard()) return false;
    }
    return true;
  }
}

final unsavedGuardsProvider = Provider<UnsavedGuards>((ref) => UnsavedGuards());
