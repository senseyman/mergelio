import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_service.dart';
import '../domain/git/git_writer.dart';
import '../domain/git/lfs.dart';
import '../domain/git/models.dart';
import 'diff_target.dart';
import 'repo_data.dart';

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
      ref.watch(lfsGenerationProvider(key.repoPath));
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

  // Order is not part of the question: a status refresh may list the same
  // files differently, and that must not discard the cached answer.
  List<String> get _sorted => [...paths]..sort();

  @override
  bool operator ==(Object other) =>
      other is LfsQuery &&
      other.source == source &&
      listEquals(other._sorted, _sorted);

  @override
  int get hashCode => Object.hash(source, Object.hashAll(_sorted));
}

/// The source every view of the working tree shares, so they share answers.
LfsSource workingTreeLfsSource(String repoPath, List<WorkingFile> working) =>
    LfsSource(repoPath: repoPath, attrsStamp: lfsAttrsStamp(working));

/// The one query for the working tree's changed files. Everything that asks
/// about the working tree goes through it, so they share one answer.
LfsQuery workingTreeLfsQuery(String repoPath, List<WorkingFile> working) =>
    LfsQuery(workingTreeLfsSource(repoPath, working), [
      for (final f in working) f.path,
    ]);

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

/// Bumped after every LFS operation. LFS state that git status cannot show —
/// the object store, pointer versus content, hooks — is watched through it.
final lfsGenerationProvider = StateProvider.family<int, String>(
  (ref, repoPath) => 0,
);

/// Whether LFS operations can run here: the repository uses LFS and git-lfs
/// is installed. Asks git-lfs nothing when the repository does not use it.
final lfsReadyProvider = FutureProvider.autoDispose.family<bool, LfsSource>((
  ref,
  source,
) async {
  if (!await ref.watch(lfsRepoProvider(source).future)) return false;
  return await ref.watch(lfsToolProvider.future) != null;
});

/// Working-tree files LFS manages that are still pointers — typically a
/// repository cloned before git-lfs was set up.
final lfsPointerFilesProvider = FutureProvider.autoDispose
    .family<Set<String>, LfsSource>((ref, source) async {
      ref.watch(lfsGenerationProvider(source.repoPath));
      if (!await ref.watch(lfsReadyProvider(source).future)) return const {};
      final git = ref.watch(gitServiceProvider);
      try {
        final r = await git.run(
          ['lfs', 'ls-files', '-l'],
          repoPath: source.repoPath,
          timeout: lfsReadTimeout,
        );
        if (!r.ok) throw GitException('git lfs ls-files', r);
        return {
          for (final e in parseLfsLsFiles(r.stdout))
            if (!e.checkedOut) e.path,
        };
      } on Object catch (e) {
        appLog.warn('LFS pointer scan failed: $e', scope: source.repoPath);
        return const {};
      }
    });

/// Whether pushing from here would upload LFS objects along with commits.
enum LfsPushReadiness { ready, toolMissing, hookMissing }

/// Whether git would actually run a hook file with the given [mode]. On
/// POSIX, git silently skips a hook that lacks an execute bit for owner,
/// group, or other; on Windows git runs hooks regardless of the execute
/// bit, so [windows] skips the mode check entirely.
bool lfsHookRuns({
  required bool exists,
  required int mode,
  required bool windows,
}) => exists && (windows || mode & 0x49 != 0);

/// The text of the repository's `pre-push` hook, or null when there is none
/// or when git would not run it (the file lacks an execute bit on POSIX).
/// Reads the filesystem, so widget tests override it.
final lfsHookTextProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  repoPath,
) async {
  ref.watch(lfsGenerationProvider(repoPath));
  final git = ref.watch(gitServiceProvider);
  try {
    // Honours core.hooksPath; relative to the repository when not absolute.
    final r = await git.run(
      ['rev-parse', '--git-path', 'hooks/pre-push'],
      repoPath: repoPath,
      timeout: lfsReadTimeout,
    );
    if (!r.ok) return null;
    final path = p.isAbsolute(r.out) ? r.out : p.join(repoPath, r.out);
    final file = File(path);
    final exists = await file.exists();
    final mode = exists ? (await file.stat()).mode : 0;
    if (!lfsHookRuns(exists: exists, mode: mode, windows: Platform.isWindows)) {
      return null;
    }
    return await file.readAsString();
  } on Object catch (e) {
    appLog.warn('Reading the pre-push hook failed: $e', scope: repoPath);
    return null;
  }
});

/// A `pre-push` hook git would skip — missing, or present but not marked
/// executable on POSIX — counts the same as no hook at all: [hookMissing].
final lfsPushReadinessProvider = FutureProvider.autoDispose
    .family<LfsPushReadiness, LfsSource>((ref, source) async {
      if (!await ref.watch(lfsRepoProvider(source).future)) {
        return LfsPushReadiness.ready;
      }
      if (await ref.watch(lfsToolProvider.future) == null) {
        return LfsPushReadiness.toolMissing;
      }
      final hook = await ref.watch(lfsHookTextProvider(source.repoPath).future);
      return hook != null && isLfsPrePushHook(hook)
          ? LfsPushReadiness.ready
          : LfsPushReadiness.hookMissing;
    });

/// What the server says about file locks in a repository.
class LfsLockState {
  const LfsLockState({
    required this.ours,
    required this.theirs,
    required this.available,
    required this.stale,
    this.refreshedAt,
  });

  /// Locks the user holds.
  final List<LfsLock> ours;

  /// Locks held by others.
  final List<LfsLock> theirs;

  /// Whether locking can be used here: LFS is set up, a remote exists and the
  /// server supports it.
  final bool available;

  /// True when the last refresh failed and [ours] and [theirs] are from an
  /// earlier one.
  final bool stale;
  final DateTime? refreshedAt;

  static const none = LfsLockState(
    ours: [],
    theirs: [],
    available: false,
    stale: false,
  );

  /// The same locks, marked as older than the latest failed refresh.
  LfsLockState asStale() => LfsLockState(
    ours: ours,
    theirs: theirs,
    available: available,
    stale: true,
    refreshedAt: refreshedAt,
  );

  /// The lock on exactly [path], the user's own first; null when none.
  LfsLock? lockFor(String path) {
    for (final l in ours) {
      if (l.path == path) return l;
    }
    for (final l in theirs) {
      if (l.path == path) return l;
    }
    return null;
  }
}

/// Set for the session once a server reports it cannot lock files, so the
/// query is not repeated on every refresh.
final lfsLocksUnsupportedProvider = StateProvider.family<bool, String>(
  (ref, repo) => false,
);

/// The last locks the server answered with, kept to show while a refresh is
/// failing.
final lfsLocksLastProvider = StateProvider.family<LfsLockState?, String>(
  (ref, repo) => null,
);

/// File locks on the server. One query per refresh, and the answer is kept for
/// the session; it follows [lfsGenerationProvider], not every change of the
/// repository data.
final lfsLocksProvider = FutureProvider.autoDispose
    .family<LfsLockState, String>((ref, repoPath) async {
      ref.keepAlive();
      ref.watch(lfsGenerationProvider(repoPath));
      // Only the `.gitattributes` state and whether a remote exists matter;
      // any other change to the repository data must not cost a server query.
      final gate = ref.watch(
        repoDataProvider(repoPath).select((d) {
          final v = d.valueOrNull;
          return v == null
              ? null
              : (
                  stamp: lfsAttrsStamp(v.working),
                  hasRemote: v.remotes.isNotEmpty,
                );
        }),
      );
      if (gate == null || !gate.hasRemote) return LfsLockState.none;
      final source = LfsSource(repoPath: repoPath, attrsStamp: gate.stamp);
      if (!await ref.watch(lfsReadyProvider(source).future)) {
        return LfsLockState.none;
      }
      if (ref.read(lfsLocksUnsupportedProvider(repoPath))) {
        return LfsLockState.none;
      }
      final git = ref.watch(gitServiceProvider);
      LfsLockState previous() {
        final last = ref.read(lfsLocksLastProvider(repoPath));
        return last?.asStale() ??
            const LfsLockState(
              ours: [],
              theirs: [],
              available: true,
              stale: true,
            );
      }

      try {
        final r = await GitWriter(git, repoPath).lfsLockList();
        if (!r.ok) {
          if (lfsLocksUnsupported(r.err)) {
            Future.microtask(
              () =>
                  ref
                          .read(lfsLocksUnsupportedProvider(repoPath).notifier)
                          .state =
                      true,
            );
            return LfsLockState.none;
          }
          throw GitException('git lfs locks', r);
        }
        final parsed = parseLfsLocksVerifyJson(r.stdout);
        if (parsed == null) throw const FormatException('unreadable lock list');
        final state = LfsLockState(
          ours: parsed.ours,
          theirs: parsed.theirs,
          available: true,
          stale: false,
          refreshedAt: DateTime.now(),
        );
        Future.microtask(
          () => ref.read(lfsLocksLastProvider(repoPath).notifier).state = state,
        );
        return state;
      } on Object catch (e) {
        appLog.warn('LFS lock query failed: $e', scope: repoPath);
        return previous();
      }
    });
