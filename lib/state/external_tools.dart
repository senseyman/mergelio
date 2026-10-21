import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/external_tools.dart';
import '../domain/git/external_git_tools.dart';

/// Starts a program the user configured — an editor, not git. Injectable so
/// tests never open a window on the developer's machine.
abstract interface class ExternalLauncher {
  /// Runs [executable] with [args] and completes, with its exit code and
  /// stderr, once it ends. Throws a [ProcessException] when it cannot be
  /// started at all.
  Future<ProcessResult> run(String executable, List<String> args);
}

class SystemExternalLauncher implements ExternalLauncher {
  /// The directories searched for a bare program name; defaults to the
  /// app's PATH widened with the usual install locations.
  final String Function()? searchPath;

  /// What a leading `~/` in the program stands for; defaults to the user's
  /// home directory.
  final String? home;
  const SystemExternalLauncher({this.searchPath, this.home});

  @override
  Future<ProcessResult> run(String executable, List<String> args) async {
    final path = (searchPath ?? externalToolPath)();
    final os = Platform.operatingSystem;
    final env = Platform.environment;
    final resolved = resolveExecutable(
      executable,
      path: path,
      os: os,
      exists: (f) => File(f).existsSync(),
      home: home ?? env['HOME'] ?? env['USERPROFILE'],
    );
    if (resolved == null) {
      // ENOENT, which is what a failed start would have reported.
      throw ProcessException(executable, args, 'not found', 2);
    }
    final lower = resolved.toLowerCase();
    final proc = await Process.start(
      resolved,
      args,
      environment: {'PATH': path},
      // A batch file is not an executable to Windows; cmd has to run it.
      runInShell:
          os == 'windows' && (lower.endsWith('.cmd') || lower.endsWith('.bat')),
    );
    await proc.stdin.close();
    // Both pipes are read to the end so a chatty editor never blocks on a
    // full one; only stderr is kept, to explain a failure.
    final stdout = proc.stdout.drain<void>();
    final stderr = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final code = await proc.exitCode;
    await stdout;
    return ProcessResult(proc.pid, code, '', await stderr);
  }
}

/// Diff tools open right now, across every repository.
final openDiffToolsProvider = StateProvider<int>((_) => 0);

final externalLauncherProvider = Provider<ExternalLauncher>(
  (_) => const SystemExternalLauncher(),
);
