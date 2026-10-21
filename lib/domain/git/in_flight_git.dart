import 'dart:async';

import 'git_service.dart';

/// [GitService] that knows how many of the commands it was given are still
/// running. An action is a run of commands with gaps between them; a count
/// above zero says it is not finished yet, which its own completion would
/// only say once it is too late to act on.
class InFlightGit implements GitService {
  final GitService inner;
  var _inFlight = 0;

  InFlightGit(this.inner);

  int get inFlight => _inFlight;

  static final _uncountedKey = Object();

  /// Runs [body] with every command it starts — after awaits too — left out
  /// of [inFlight]. For work that waits on something other than the
  /// repository, a remote above all, which says nothing about when the
  /// repository will next change.
  static Future<T> uncounted<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_uncountedKey: true});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (Zone.current[_uncountedKey] == true) {
      return inner.run(
        args,
        repoPath: repoPath,
        timeout: timeout,
        environment: environment,
        cancel: cancel,
        stdin: stdin,
      );
    }
    _inFlight++;
    try {
      return await inner.run(
        args,
        repoPath: repoPath,
        timeout: timeout,
        environment: environment,
        cancel: cancel,
        stdin: stdin,
      );
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<String> version() => inner.version();

  @override
  Future<bool> isRepository(String path) => inner.isRepository(path);
}
