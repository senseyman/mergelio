import 'package:mergelio/domain/git/git_service.dart';

/// [SystemGitService] with global and system git config ignored, so the
/// developer's own setup — signing, core.hooksPath, templates — cannot change
/// what integration tests observe.
class HermeticGit implements GitService {
  const HermeticGit();

  static const _inner = SystemGitService();
  static const _isolation = {
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_CONFIG_NOSYSTEM': '1',
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _inner.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {...?environment, ..._isolation},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}
