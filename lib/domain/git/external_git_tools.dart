import 'dart:io';

import '../external_tools.dart';
import 'git_service.dart';
import 'in_flight_git.dart';

/// The git side of handing a file to the user's diff or merge tool: reading
/// which tool is set, and running `difftool` / `mergetool` long enough for
/// the user to finish in it.
class ExternalGitTools {
  final GitService git;
  final String repoPath;
  const ExternalGitTools(this.git, this.repoPath);

  /// The diff and merge tool keys in effect. git exits 1 when none is set;
  /// anything else non-zero is a config it cannot read.
  Future<ExternalToolConfig> config() async {
    final r = await git.run([
      'config',
      '-z',
      '--get-regexp',
      kExternalToolConfigPattern,
    ], repoPath: repoPath);
    if (r.exitCode == 1) return ExternalToolConfig.empty;
    if (!r.ok) throw GitException('git config failed', r);
    return parseToolConfig(r.stdout);
  }

  /// What [sha] is compared against: its first parent, or the empty tree for
  /// a root commit, which has none. The empty tree is asked of git rather
  /// than spelled out, since it differs in a SHA-256 repository.
  Future<String> diffBase(String sha) async {
    final parent = await git.run([
      'rev-parse',
      '--verify',
      '--quiet',
      '$sha^',
    ], repoPath: repoPath);
    if (parent.ok && parent.out.isNotEmpty) return parent.out;
    final empty = await git.run(
      ['hash-object', '-t', 'tree', '--stdin'],
      repoPath: repoPath,
      stdin: '',
    );
    if (!empty.ok) throw GitException('git hash-object failed', empty);
    return empty.out;
  }

  /// Runs `git difftool` with [args] until the tool is closed.
  Future<GitResult> difftool(List<String> args, {GitCancel? cancel}) =>
      _runTool(args, cancel);

  /// Runs `git mergetool` with [args] until the tool is closed. git stages
  /// the file when the tool reports success; nothing is committed.
  Future<GitResult> mergetool(List<String> args, {GitCancel? cancel}) =>
      _runTool(args, cancel);

  /// Left out of [InFlightGit]'s count: an open tool is a window the user
  /// reads at their own pace, not repository work about to finish, and
  /// counting it would hold every refresh back for as long as it is open.
  Future<GitResult> _runTool(List<String> args, GitCancel? cancel) =>
      InFlightGit.uncounted(
        () => git.run(
          args,
          repoPath: repoPath,
          timeout: kExternalToolTimeout,
          cancel: cancel,
          // git starts the tool through PATH, which a Finder or Dock launch
          // keeps to the system directories.
          environment: {'PATH': externalToolPath()},
        ),
      );
}

/// The app's PATH widened with [toolSearchDirs], for starting the user's
/// editor or a diff tool.
String externalToolPath() {
  final env = Platform.environment;
  return toolSearchPath(
    env['PATH'],
    os: Platform.operatingSystem,
    home: env['HOME'] ?? env['USERPROFILE'] ?? '',
  );
}
