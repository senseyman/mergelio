import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  });

  /// True if [path] contains a git repository. Never throws: a missing or
  /// inaccessible path simply is not a repository.
  Future<bool> isRepository(String path);
}

class SystemGitService implements GitService {
  final String gitBinary;

  /// Default guard against hung git processes (e.g. a network op that stalls).
  final Duration defaultTimeout;

  const SystemGitService({
    this.gitBinary = 'git',
    this.defaultTimeout = const Duration(seconds: 30),
  });

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
  }) async {
    final Process proc;
    try {
      proc = await Process.start(
        gitBinary,
        args,
        workingDirectory: repoPath,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      throw GitException('failed to run git ${args.join(' ')}: ${e.message}');
    }

    // Git emits UTF-8 regardless of platform; decode explicitly so output is
    // correct on Windows (systemEncoding would use the ANSI code page). Drain
    // both streams eagerly to avoid the child blocking on a full pipe buffer.
    final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
    final stderrFuture = proc.stderr.transform(utf8.decoder).join();

    try {
      final exitCode = await proc.exitCode.timeout(timeout ?? defaultTimeout);
      final output = await Future.wait([stdoutFuture, stderrFuture]);
      return GitResult(exitCode, output[0], output[1]);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      final limit = timeout ?? defaultTimeout;
      throw GitException(
        'git ${args.join(' ')} timed out after ${limit.inSeconds}s',
      );
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
