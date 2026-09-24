import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drops one registration. Calling it again does nothing.
typedef DropGuard = void Function();

/// Asked before something takes work away: leaving Files mode, closing a
/// repository tab, quitting. Widgets register a guard for their repository
/// while they are mounted; a repository with nothing mounted has nothing to
/// lose, so it answers yes.
///
/// A guard returns false when the user backed out, which cancels whatever was
/// about to happen.
///
/// One repository can hold several at once — an editor pane guards unsaved
/// text, a bisect bar guards a detached HEAD — and they are not alternatives:
/// each protects something the other knows nothing about. So registering adds
/// rather than replaces, and a registration can only be dropped through the
/// callback that created it. Dropping by repository path would let whichever
/// widget was torn down first carry the others' guards off with it, which is
/// how work goes missing without a word.
class UnsavedGuards {
  final _guards = <String, List<Future<bool> Function()>>{};

  DropGuard register(String repoPath, Future<bool> Function() guard) {
    (_guards[repoPath] ??= []).add(guard);
    var dropped = false;
    return () {
      if (dropped) return;
      dropped = true;
      final guards = _guards[repoPath];
      if (guards == null) return;
      final at = guards.indexWhere((g) => identical(g, guard));
      if (at >= 0) guards.removeAt(at);
      if (guards.isEmpty) _guards.remove(repoPath);
    };
  }

  Future<bool> confirm(String repoPath) => _ask(_guards[repoPath]);

  /// Asks every repository, stopping at the first refusal so the user is not
  /// walked through prompts for a quit they have already cancelled.
  Future<bool> confirmAll() async {
    for (final guards in [..._guards.values]) {
      if (!await _ask(guards)) return false;
    }
    return true;
  }

  /// Copied before iterating: a guard is free to open a dialog, and whatever
  /// the user does there may register or drop guards while this walk is
  /// still in progress.
  Future<bool> _ask(List<Future<bool> Function()>? guards) async {
    for (final guard in [...?guards]) {
      if (!await guard()) return false;
    }
    return true;
  }
}

final unsavedGuardsProvider = Provider<UnsavedGuards>((ref) => UnsavedGuards());
