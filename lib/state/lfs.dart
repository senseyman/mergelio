import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/lfs.dart';
import '../domain/git/models.dart';
import 'diff_target.dart';

/// Every LFS read gets this long. Attribute and blob lookups over a commit
/// with thousands of files take longer than git's 30-second default.
const lfsReadTimeout = Duration(seconds: 60);

/// Where attributes and blobs are read from: the working tree when [rev] is
/// null, otherwise that revision. [parentRev] is where a path deleted at
/// [rev] still exists. [attrsStamp] changes whenever a `.gitattributes` file
/// changes state in the working tree, so the working-tree answer is
/// recomputed then and only then.
class LfsSource {
  final String repoPath;
  final String? rev;
  final String? parentRev;
  final String attrsStamp;
  const LfsSource({
    required this.repoPath,
    this.rev,
    this.parentRev,
    this.attrsStamp = '',
  });

  /// A full object id never changes what it names, so answers about it can
  /// be kept for the session.
  bool get isImmutable =>
      rev != null && RegExp(r'^([0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(rev!);

  @override
  bool operator ==(Object other) =>
      other is LfsSource &&
      other.repoPath == repoPath &&
      other.rev == rev &&
      other.parentRev == parentRev &&
      other.attrsStamp == attrsStamp;

  @override
  int get hashCode => Object.hash(repoPath, rev, parentRev, attrsStamp);
}

/// A fingerprint of the working tree's `.gitattributes` entries. Editing,
/// staging or committing one of them changes it.
String lfsAttrsStamp(List<WorkingFile> working) => [
  for (final f in working)
    if (f.path == '.gitattributes' || f.path.endsWith('/.gitattributes'))
      '${f.path}:${f.index.name}:${f.worktree.name}',
].join('\x00');

/// The source a diff sheet target reads from.
LfsSource lfsSourceFor(DiffTarget t, {List<WorkingFile> working = const []}) =>
    t.isWorkingTree
    ? LfsSource(repoPath: t.repoPath, attrsStamp: lfsAttrsStamp(working))
    : LfsSource(
        repoPath: t.repoPath,
        rev: t.commitSha,
        parentRev: t.baseRev ?? '${t.commitSha}^',
      );

/// The installed git-lfs version, or null when there is none. Asked once per
/// session: installing it means restarting the app anyway, as its hooks and
/// filters are only picked up by new git processes started from a fresh
/// environment.
final lfsToolProvider = FutureProvider<String?>((ref) async {
  try {
    final r = await ref.watch(gitServiceProvider).run([
      'lfs',
      'version',
    ], timeout: lfsReadTimeout);
    return r.ok ? parseLfsVersion(r.stdout) : null;
  } on Object catch (e) {
    appLog.warn('git lfs version failed: $e');
    return null;
  }
});

/// Whether any tracked `.gitattributes` at [source] routes files through LFS.
/// Everything else LFS-related waits on this, so a repository without LFS
/// costs one grep and nothing more.
final lfsRepoProvider = FutureProvider.autoDispose.family<bool, LfsSource>((
  ref,
  source,
) async {
  if (source.isImmutable) ref.keepAlive();
  try {
    final r = await ref
        .watch(gitServiceProvider)
        .run(
          [
            'grep',
            '-l',
            '-z',
            '-F',
            '-e',
            'filter=lfs',
            if (source.rev != null) source.rev!,
            '--',
            ':(glob)**/.gitattributes',
          ],
          repoPath: source.repoPath,
          timeout: lfsReadTimeout,
        );
    // Exit 1 is "no match". An empty success is treated the same way: a
    // match always names a file.
    return r.ok && r.stdout.isNotEmpty;
  } on Object catch (e) {
    appLog.warn('LFS attribute scan failed: $e', scope: source.repoPath);
    return false;
  }
});

/// Where downloaded LFS objects live for the repository at [repoPath], or
/// null when git could not say.
final lfsObjectsDirProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, repoPath) async {
      final git = ref.watch(gitServiceProvider);
      try {
        final common = await git.run(
          ['rev-parse', '--git-common-dir'],
          repoPath: repoPath,
          timeout: lfsReadTimeout,
        );
        if (!common.ok) return null;
        final storage = await git.run(
          ['config', '--get', 'lfs.storage'],
          repoPath: repoPath,
          timeout: lfsReadTimeout,
        );
        return lfsObjectsDir(
          repoPath: repoPath,
          commonDir: common.out,
          lfsStorage: storage.ok ? storage.out : null,
        );
      } on Object catch (e) {
        appLog.warn('LFS storage lookup failed: $e', scope: repoPath);
        return null;
      }
    });

/// Whether the object with this oid has been downloaded. Reads the
/// filesystem, so widget tests override it. Never downloaded and unreadable
/// both mean "not present": a malformed oid or a filesystem error yields
/// false rather than failing the diff sheet.
final lfsObjectPresentProvider = FutureProvider.autoDispose
    .family<bool, ({String repoPath, String oid})>((ref, key) async {
      try {
        final dir = await ref.watch(lfsObjectsDirProvider(key.repoPath).future);
        if (dir == null) return false;
        return await File(lfsObjectPath(dir, key.oid)).exists();
      } on Object catch (e) {
        appLog.warn('LFS object lookup failed: $e', scope: key.repoPath);
        return false;
      }
    });

/// Repositories whose "git-lfs isn't installed" banner was dismissed in this
/// session.
final lfsBannerDismissedProvider = StateProvider<Set<String>>((ref) => {});
