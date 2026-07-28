import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/concurrency.dart';
import '../../core/logging.dart';

/// Result of a git invocation. [stdout]/[stderr] are the raw, undecorated
/// streams (whitespace preserved — diffs and blob content depend on it);
/// use [out]/[err] where a trimmed single value is expected.
class GitResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const GitResult(this.exitCode, this.stdout, this.stderr);

  bool get ok => exitCode == 0;
  String get out => stdout.trim();
  String get err => stderr.trim();
}

class GitException implements Exception {
  final String message;
  final GitResult? result;
  GitException(this.message, [this.result]);
  @override
  String toString() =>
      'GitException: $message${result != null ? '\n${result!.err}' : ''}';
}

/// Abstraction over the Git engine. UI never shells out directly; it depends
/// on this interface. [SystemGitService] uses the system `git` binary;
/// libgit2 FFI may be added later for fast reads.
abstract class GitService {
  /// `git --version`, e.g. "git version 2.55.0".
  Future<String> version();

  /// Run an arbitrary git command in [repoPath] (or cwd if null). The process
  /// is killed and a [GitException] thrown if it exceeds [timeout].
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  });

  /// True if [path] contains a git repository. Never throws: a missing or
  /// inaccessible path simply is not a repository.
  Future<bool> isRepository(String path);
}

/// Process-wide cap on concurrent git subprocesses.
///
/// The file-descriptor limit is a property of the process, not of any one
/// service instance, so the gate is shared. Twelve children (~48 descriptors)
/// leaves ample headroom under the 256 a macOS GUI app is given, while still
/// keeping every core busy.
final ConcurrencyGate _sharedGitGate = ConcurrencyGate(12);

class SystemGitService implements GitService {
  final String gitBinary;

  /// Default guard against hung git processes (e.g. a network op that stalls).
  final Duration defaultTimeout;

  /// Overridable for tests; defaults to the process-wide gate.
  final ConcurrencyGate? gate;

  /// Overridable for tests; defaults to the app-wide logger.
  final AppLogger? logger;

  /// Commands slower than this are logged as warnings rather than debug, so a
  /// repository that is merely large stands out from one that is starved.
  final Duration slowAfter;

  const SystemGitService({
    this.gitBinary = 'git',
    this.defaultTimeout = const Duration(seconds: 30),
    this.gate,
    this.logger,
    this.slowAfter = const Duration(seconds: 5),
  });

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    // The queue wait deliberately sits outside the timeout below: a command
    // held back by the gate has not started, so it must not be timed out for
    // the time it spent queued.
    return (gate ?? _sharedGitGate).run(
      () => _spawn(args, repoPath, timeout, environment),
    );
  }

  Future<GitResult> _spawn(
    List<String> args,
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  ) async {
    final started = DateTime.now();
    // Counts this command too. Read next to the duration it tells you which
    // kind of slow this is: a high number means contention with siblings, a
    // low one means the command itself is expensive.
    final inFlight = (gate ?? _sharedGitGate).inFlight;

    final Process proc;
    try {
      proc = await Process.start(
        gitBinary,
        args,
        workingDirectory: repoPath,
        environment: environment,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      throw GitException('failed to run git ${args.join(' ')}: ${e.message}');
    }

    // Nothing is ever written to a git child, so close the pipe immediately:
    // it releases a descriptor early and stops a command that would read stdin
    // from waiting for input that never comes.
    unawaited(proc.stdin.close().catchError((_) {}));

    // Git emits UTF-8 regardless of platform; decode explicitly so output is
    // correct on Windows (systemEncoding would use the ANSI code page). Drain
    // both streams eagerly to avoid the child blocking on a full pipe buffer.
    final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
    final stderrFuture = proc.stderr.transform(utf8.decoder).join();

    try {
      final exitCode = await proc.exitCode.timeout(timeout ?? defaultTimeout);
      final output = await Future.wait([stdoutFuture, stderrFuture]);
      _record(args, repoPath, started, inFlight, bytes: output[0].length);
      return GitResult(exitCode, output[0], output[1]);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      final limit = timeout ?? defaultTimeout;
      _record(args, repoPath, started, inFlight, timedOut: true);
      throw GitException(
        'git ${args.join(' ')} timed out after ${limit.inSeconds}s',
      );
    }
  }

  /// Notes what the command cost. Long commands are the whole point of this
  /// record, so they are raised to warning level; the rest stay at debug.
  void _record(
    List<String> args,
    String? repoPath,
    DateTime started,
    int inFlight, {
    int? bytes,
    bool timedOut = false,
  }) {
    final elapsed = DateTime.now().difference(started);
    final where = repoPath == null ? '' : ' in $repoPath';
    final size = bytes == null ? '' : ', ${bytes}B';
    final message =
        '${gitBinary.split('/').last} ${args.join(' ')}$where — '
        '${elapsed.inMilliseconds}ms, $inFlight in flight$size'
        '${timedOut ? ', TIMED OUT' : ''}';
    final log = logger ?? appLog;
    if (timedOut || elapsed >= slowAfter) {
      log.warn(message, scope: 'git');
    } else {
      log.debug(message, scope: 'git');
    }
  }

  @override
  Future<String> version() async {
    final r = await run(['--version']);
    if (!r.ok) throw GitException('git --version failed', r);
    return r.out;
  }

  @override
  Future<bool> isRepository(String path) async {
    try {
      final r = await run([
        'rev-parse',
        '--is-inside-work-tree',
      ], repoPath: path);
      return r.ok && r.out == 'true';
    } on GitException {
      // Nonexistent/inaccessible working directory → not a repository.
      return false;
    }
  }
}
