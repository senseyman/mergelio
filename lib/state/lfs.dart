import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
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
  final git = ref.watch(gitServiceProvider);
  try {
    final rev = source.rev;
    final revArgs = rev == null
        ? const <String>[]
        : revisionArgs(rev, await ref.watch(gitVersionProvider.future));
    if (revArgs == null) {
      appLog.warn(
        'LFS attribute scan skipped: this git cannot safely name $rev',
        scope: source.repoPath,
      );
      return false;
    }
    final r = await git.run(
      [
        'grep',
        '-l',
        '-z',
        '-E',
        '-e',
        lfsAttributePattern,
        ...revArgs,
        '--',
        ':(glob)**/.gitattributes',
      ],
      repoPath: source.repoPath,
      timeout: lfsReadTimeout,
    );
    // Exit 1 is "no match". Anything else non-zero is git failing, which is
    // worth a line in the log: otherwise LFS support silently switches off.
    if (!r.ok && r.exitCode != 1) {
      appLog.warn(
        'LFS attribute scan failed: exit ${r.exitCode} ${r.err}',
        scope: source.repoPath,
      );
    }
    // An empty success is treated as no match too: a match always names a
    // file.
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

/// Which of [paths] LFS manages at [source].
class LfsQuery {
  final LfsSource source;
  final List<String> paths;
  const LfsQuery(this.source, this.paths);

  @override
  bool operator ==(Object other) =>
      other is LfsQuery &&
      other.source == source &&
      listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(source, Object.hashAll(paths));
}

/// The subset of the query's paths that LFS manages, empty when that cannot
/// be told. A failure here only costs badges, so it is logged and swallowed
/// rather than shown.
final lfsPathsProvider = FutureProvider.autoDispose
    .family<Set<String>, LfsQuery>((ref, query) async {
      final source = query.source;
      if (source.isImmutable) ref.keepAlive();
      if (query.paths.isEmpty) return const {};
      if (!await ref.watch(lfsRepoProvider(source).future)) return const {};
      final git = ref.watch(gitServiceProvider);
      try {
        final rev = source.rev;
        if (rev == null) return await _checkAttr(git, source, query.paths);
        final gitVersion = await ref.watch(gitVersionProvider.future);
        if (supportsCheckAttrSource(gitVersion)) {
          return await _checkAttr(git, source, query.paths, rev: rev);
        }
        return await _pointerScan(git, source, rev, query.paths, gitVersion);
      } on Object catch (e) {
        appLog.warn('LFS path lookup failed: $e', scope: source.repoPath);
        return const {};
      }
    });

Future<Set<String>> _checkAttr(
  GitService git,
  LfsSource source,
  List<String> paths, {
  String? rev,
}) async {
  final r = await git.run(
    ['check-attr', if (rev != null) '--source=$rev', '-z', '--stdin', 'filter'],
    repoPath: source.repoPath,
    stdin: '${paths.join('\x00')}\x00',
    timeout: lfsReadTimeout,
  );
  if (!r.ok) throw GitException('check-attr failed', r);
  return parseCheckAttrLfs(r.stdout);
}

/// For a git too old to read a revision's own attributes: find the blobs that
/// are pointers. The grep narrows the candidates to files quoting the pointer
/// spec, the size check drops anything too big to be one, and only those few
/// are read and parsed.
Future<Set<String>> _pointerScan(
  GitService git,
  LfsSource source,
  String rev,
  List<String> paths,
  String gitVersion,
) async {
  // One path per stdin line below, so a path with a newline cannot be asked
  // about; it goes unbadged.
  final wanted = {
    for (final p in paths)
      if (!p.contains('\n')) p,
  };

  Future<Set<String>> grep(String at) async {
    // An option-shaped revision git cannot guard is refused; the trailing
    // `--` keeps the revision from being read as a path.
    final revArgs = revisionArgs(at, gitVersion);
    if (revArgs == null) {
      throw ArgumentError.value(at, 'rev', 'cannot be named safely');
    }
    final r = await git.run(
      ['grep', '-l', '-z', '-F', '-e', lfsPointerVersion, ...revArgs, '--'],
      repoPath: source.repoPath,
      timeout: lfsReadTimeout,
    );
    if (r.ok) return parseGrepRevPaths(r.stdout, at);
    // Exit 1 means "no match", a normal outcome for a grep. Anything else
    // (bad rev, corrupt object) is a real failure and must not be read as
    // "nothing here".
    if (r.exitCode == 1) return const {};
    throw GitException('grep failed', r);
  }

  // Each candidate is looked up where it exists: at the revision, or for a
  // path deleted there, in the parent.
  final specs = <String, String>{}; // path → rev:path
  final atRev = (await grep(rev)).intersection(wanted);
  for (final p in atRev) {
    specs[p] = '$rev:$p';
  }

  // A path not found as a pointer at rev is either gone from rev (so the
  // parent has to answer for it) or still there but as a plain blob now —
  // moved out of LFS. Only the first case may fall back to the parent:
  // asking the parent about a path that still exists at rev would badge it
  // from stale history instead of the content actually at rev.
  final remaining = wanted.difference(atRev);
  final parent = source.parentRev;
  if (parent != null && remaining.isNotEmpty) {
    final remainingOrder = remaining.toList();
    final exists = await git.run(
      ['cat-file', '--batch-check'],
      repoPath: source.repoPath,
      stdin: '${[for (final p in remainingOrder) '$rev:$p'].join('\n')}\n',
      timeout: lfsReadTimeout,
    );
    if (!exists.ok) {
      throw GitException('cat-file --batch-check failed', exists);
    }
    final existing = parseBatchCheck(exists.stdout);
    final deletedAtRev = <String>{
      for (var i = 0; i < remainingOrder.length && i < existing.length; i++)
        if (existing[i] == null) remainingOrder[i],
    };
    if (deletedAtRev.isNotEmpty) {
      for (final p in (await grep(parent)).intersection(deletedAtRev)) {
        specs.putIfAbsent(p, () => '$parent:$p');
      }
    }
  }
  if (specs.isEmpty) return const {};

  final order = specs.keys.toList();
  final check = await git.run(
    ['cat-file', '--batch-check'],
    repoPath: source.repoPath,
    stdin: '${[for (final p in order) specs[p]!].join('\n')}\n',
    timeout: lfsReadTimeout,
  );
  if (!check.ok) throw GitException('cat-file --batch-check failed', check);
  final sizes = parseBatchCheck(check.stdout);
  final oidToPaths = <String, List<String>>{};
  for (var i = 0; i < order.length && i < sizes.length; i++) {
    final entry = sizes[i];
    if (entry == null || entry.$2 > lfsPointerMaxBytes) continue;
    oidToPaths.putIfAbsent(entry.$1, () => []).add(order[i]);
  }
  if (oidToPaths.isEmpty) return const {};

  final oids = oidToPaths.keys.toList();
  final batch = await git.run(
    ['cat-file', '--batch'],
    repoPath: source.repoPath,
    stdin: '${oids.join('\n')}\n',
    timeout: lfsReadTimeout,
  );
  if (!batch.ok) throw GitException('cat-file --batch failed', batch);
  return {
    for (final MapEntry(key: oid, value: text) in parseCatFileBatch(
      batch.stdout,
      oids,
    ).entries)
      if (parseLfsPointer(text) != null) ...?oidToPaths[oid],
  };
}
