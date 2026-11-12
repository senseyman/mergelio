import 'dart:io';
import 'dart:typed_data';

import 'git_service.dart';

/// Configuration and environment laid over every git command.
class GitNetworkOverrides {
  /// git config keys and values, passed the way `-c` would pass them.
  final Map<String, String> config;

  /// Environment variables, replacing inherited ones.
  final Map<String, String> env;

  const GitNetworkOverrides({this.config = const {}, this.env = const {}});

  static const none = GitNetworkOverrides();

  bool get isEmpty => config.isEmpty && env.isEmpty;

  /// [environment] with these overrides applied.
  ///
  /// Config goes through `GIT_CONFIG_COUNT` (git 2.31+) rather than `-c`:
  /// a proxy url can carry a password, and a process's arguments are visible
  /// to every user on the machine while its environment is not. Entries are
  /// appended after any the caller passed or the app [inherited], so config
  /// already given that way keeps working.
  Map<String, String> applyTo(
    Map<String, String> environment, {
    required Map<String, String> inherited,
  }) {
    final start =
        int.tryParse(
          environment['GIT_CONFIG_COUNT'] ??
              inherited['GIT_CONFIG_COUNT'] ??
              '',
        ) ??
        0;
    var i = start;
    return {
      ...environment,
      ...env,
      for (final MapEntry(:key, :value) in config.entries) ...{
        'GIT_CONFIG_KEY_$i': key,
        'GIT_CONFIG_VALUE_${i++}': value,
      },
      if (config.isNotEmpty) 'GIT_CONFIG_COUNT': '$i',
    };
  }
}

/// A [GitService] that lays [overrides] over every command it runs.
///
/// Every command, not only fetch and push: a checkout reaches the network
/// too when git-lfs's smudge filter downloads objects, and that filter
/// inherits this environment. Proxy config means nothing to a command that
/// never opens a connection.
///
/// [overrides] is asked at every call rather than captured, so a changed
/// setting applies to the next fetch without rebuilding anything that holds
/// this service.
class NetworkEnvGitService implements GitService, GitBytesRunner {
  final GitService _inner;
  final GitNetworkOverrides Function() overrides;
  final Map<String, String> _inherited;

  NetworkEnvGitService(
    this._inner,
    this.overrides, {
    Map<String, String>? inherited,
  }) : _inherited = inherited ?? Platform.environment;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    final o = overrides();
    return _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: o.isEmpty
          ? environment
          : o.applyTo(environment ?? const {}, inherited: _inherited),
      cancel: cancel,
      stdin: stdin,
    );
  }

  @override
  Future<Uint8List?> runBytes(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    required int maxBytes,
  }) => (_inner as GitBytesRunner).runBytes(
    args,
    repoPath: repoPath,
    timeout: timeout,
    maxBytes: maxBytes,
  );

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}
