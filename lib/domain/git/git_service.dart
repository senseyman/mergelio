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

/// The operation was abandoned on purpose. Separate from a plain
/// [GitException] so the UI can say so instead of reporting a failure.
class GitCancelledException extends GitException {
  GitCancelledException(super.message);
}

/// Handle on a running git command. [cancel] kills the child, so an operation
/// stalled on an unreachable remote can be given up on immediately instead of
/// holding its lane until the timeout runs out.
class GitCancel {
  Process? _proc;
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _proc?.kill(ProcessSignal.sigkill);
  }

  /// Binds the child once it exists. A cancel that arrived while the process
  /// was still starting applies the moment it does.
  void _attach(Process proc) {
    _proc = proc;
    if (_cancelled) proc.kill(ProcessSignal.sigkill);
  }
}

/// SSH options appended to every command that talks to a remote. A host that
/// accepts the TCP connection and then goes quiet otherwise stalls until the
/// operation's own timeout, minutes later; these give up in seconds.
const sshWatchdogOptions = [
  '-o',
  'ConnectTimeout=10',
  '-o',
  'ServerAliveInterval=5',
  '-o',
  'ServerAliveCountMax=3',
];

/// [base] (whatever ssh command the user configured) followed by
/// [sshWatchdogOptions]. ssh keeps the first value it sees for an option, so
/// appending leaves anything the user set in charge.
String sshCommandWith(String? base) {
  final cmd = base?.trim();
  return '${cmd == null || cmd.isEmpty ? 'ssh' : cmd} '
      '${sshWatchdogOptions.join(' ')}';
}

/// Abstraction over the Git engine. UI never shells out directly; it depends
/// on this interface. [SystemGitService] uses the system `git` binary;
/// libgit2 FFI may be added later for fast reads.
abstract class GitService {
  /// `git --version`, e.g. "git version 2.55.0".
  Future<String> version();

  /// Run an arbitrary git command in [repoPath] (or cwd if null). The process
  /// is killed and a [GitException] thrown if it exceeds [timeout]. Passing a
  /// [cancel] handle lets the caller kill the child before that.
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
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
    GitCancel? cancel,
  }) async {
    // The queue wait deliberately sits outside the timeout below: a command
    // held back by the gate has not started, so it must not be timed out for
    // the time it spent queued.
    return (gate ?? _sharedGitGate).run(
      () => _spawn(args, repoPath, timeout, environment, cancel),
    );
  }

  Future<GitResult> _spawn(
    List<String> args,
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
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

    cancel?._attach(proc);

    // Nothing is ever written to a git child, so close the pipe immediately:
    // it releases a descriptor early and stops a command that would read stdin
    // from waiting for input that never comes.
    unawaited(proc.stdin.close().catchError((_) {}));

    // Git emits UTF-8 regardless of platform; decode explicitly so output is
    // correct on Windows (systemEncoding would use the ANSI code page). Drain
    // both streams eagerly to avoid the child blocking on a full pipe buffer.
    // Malformed bytes are tolerated: filenames and commit messages written in
    // another encoding are the repository's history, not an error to raise.
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutFuture = proc.stdout.transform(decoder).join();
    final stderrFuture = proc.stderr.transform(decoder).join();

    // Claim the errors before anyone waits on them. The timeout path below
    // abandons both futures, and a stream error nobody listens for surfaces
    // later as an unhandled async error, far from the command that caused it.
    // The success path still awaits the originals, so a real failure is not
    // swallowed — this only guarantees someone is listening.
    unawaited(stdoutFuture.catchError((Object _) => ''));
    unawaited(stderrFuture.catchError((Object _) => ''));

    try {
      final exitCode = await proc.exitCode.timeout(timeout ?? defaultTimeout);
      final output = await Future.wait([stdoutFuture, stderrFuture]);
      _record(args, repoPath, started, inFlight, bytes: output[0].length);
      // A killed child exits non-zero with nothing useful to say; report the
      // abandonment rather than a failure the user did not cause.
      if (cancel?.isCancelled ?? false) {
        throw GitCancelledException('git ${args.join(' ')} cancelled');
      }
      return GitResult(exitCode, output[0], output[1]);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      // Wait briefly for the killed process to release its resources. Without
      // this the OS may hold the pid slot as a zombie until the next wait.
      await proc.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
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
