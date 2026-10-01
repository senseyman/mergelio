import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'git_service.dart';

/// `git count-objects -v`, sizes converted from git's KiB to bytes.
class CountObjects {
  final int looseCount;
  final int looseBytes;
  final int packedCount;
  final int packCount;
  final int packBytes;
  final int prunePackable;
  final int garbageCount;
  final int garbageBytes;

  const CountObjects({
    this.looseCount = 0,
    this.looseBytes = 0,
    this.packedCount = 0,
    this.packCount = 0,
    this.packBytes = 0,
    this.prunePackable = 0,
    this.garbageCount = 0,
    this.garbageBytes = 0,
  });
}

/// Reads `count-objects -v`. `-v` rather than `-vH`: plain KiB integers keep
/// the parse independent of git's human-readable units.
CountObjects parseCountObjects(String out) {
  final v = <String, int>{};
  for (final line in const LineSplitter().convert(out)) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final n = int.tryParse(line.substring(colon + 1).trim());
    if (n != null) v[line.substring(0, colon).trim()] = n;
  }
  return CountObjects(
    looseCount: v['count'] ?? 0,
    looseBytes: (v['size'] ?? 0) * 1024,
    packedCount: v['in-pack'] ?? 0,
    packCount: v['packs'] ?? 0,
    packBytes: (v['size-pack'] ?? 0) * 1024,
    prunePackable: v['prune-packable'] ?? 0,
    garbageCount: v['garbage'] ?? 0,
    garbageBytes: (v['size-garbage'] ?? 0) * 1024,
  );
}

/// One blob from the object listing, with the first path it was seen at.
class BlobEntry {
  final String sha;
  final int size;

  /// Empty when git reached the blob without a path.
  final String path;

  const BlobEntry({required this.sha, required this.size, required this.path});

  Map<String, dynamic> toJson() => {'sha': sha, 'size': size, 'path': path};

  factory BlobEntry.fromJson(Map<String, dynamic> j) => BlobEntry(
    sha: j['sha'] as String,
    size: j['size'] as int,
    path: j['path'] as String? ?? '',
  );
}

/// The format [topBlobs] reads, for `cat-file --batch-all-objects
/// --batch-check`. No path: git lists the object store itself, which is far
/// cheaper than walking history for names, and paths are found afterwards for
/// the few blobs that make the list.
const allObjectsFormat = '%(objecttype) %(objectname) %(objectsize)';

final _objectName = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

/// The [n] largest blobs in [batch], largest first; [BlobEntry.path] is left
/// empty. Equal sizes order by sha, so a rescan of the same objects lists
/// them the same way.
///
/// Holds at most [n] entries however many objects the listing has: a large
/// repository has millions, and a list of all of them only to keep 25 would
/// cost more than the listing itself. Lines that are not a blob, an object
/// name and a size are skipped.
List<BlobEntry> topBlobs(String batch, int n) {
  if (n <= 0) return const [];
  // Kept sorted, largest first.
  final top = <BlobEntry>[];
  bool before(BlobEntry a, BlobEntry b) =>
      a.size != b.size ? a.size > b.size : a.sha.compareTo(b.sha) < 0;
  var start = 0;
  while (start < batch.length) {
    var end = batch.indexOf('\n', start);
    if (end < 0) end = batch.length;
    final lineStart = start;
    start = end + 1;
    if (!batch.startsWith('blob ', lineStart)) continue;
    final shaEnd = batch.indexOf(' ', lineStart + 5);
    if (shaEnd < 0 || shaEnd >= end) continue;
    final size = int.tryParse(batch.substring(shaEnd + 1, end).trim());
    if (size == null) continue;
    if (top.length == n && size < top.last.size) continue;
    final sha = batch.substring(lineStart + 5, shaEnd);
    if (!_objectName.hasMatch(sha)) continue;
    final entry = BlobEntry(sha: sha, size: size, path: '');
    if (top.length == n && !before(entry, top.last)) continue;
    var i = top.length;
    while (i > 0 && before(entry, top[i - 1])) {
      i--;
    }
    top.insert(i, entry);
    if (top.length > n) top.removeLast();
  }
  return top;
}

/// The log format [parseBlobOrigin] reads, used with `--name-only`.
const blobOriginFormat = '%H%x1f%h%x1f%aI%x1f%s';

/// The commit that first brought a blob into history.
class IntroducingCommit {
  final String sha;
  final String shortSha;

  /// ISO-8601 author date.
  final String date;
  final String subject;

  const IntroducingCommit({
    required this.sha,
    required this.shortSha,
    required this.date,
    required this.subject,
  });

  Map<String, dynamic> toJson() => {
    'sha': sha,
    'shortSha': shortSha,
    'date': date,
    'subject': subject,
  };

  factory IntroducingCommit.fromJson(Map<String, dynamic> j) =>
      IntroducingCommit(
        sha: j['sha'] as String,
        shortSha: j['shortSha'] as String,
        date: j['date'] as String,
        subject: j['subject'] as String,
      );
}

/// The first record of `log --reverse --name-only --find-object=<sha>`: the
/// oldest commit that touched the blob, which is the one that added it, and
/// the path it added it at. `--find-object` narrows the listed paths to the
/// ones holding that blob. No commit and an empty path when nothing on any
/// ref reaches it.
({IntroducingCommit? commit, String path}) parseBlobOrigin(String out) {
  final lines = const LineSplitter().convert(out);
  final f = lines.isEmpty ? const <String>[] : lines.first.split('\x1f');
  if (f.length < 4) return (commit: null, path: '');
  var path = '';
  for (final line in lines.skip(1)) {
    if (line.contains('\x1f')) break; // the next commit's header
    if (line.isNotEmpty) {
      path = line;
      break;
    }
  }
  return (
    commit: IntroducingCommit(
      sha: f[0],
      shortSha: f[1],
      date: f[2],
      subject: f.sublist(3).join('\x1f'),
    ),
    path: path,
  );
}

/// A large blob and where it came from. [commit] is null, and the path
/// empty, when no commit on any ref reaches it — an object only a reflog, a
/// stash or nothing at all still holds, which takes the space all the same.
class BigBlob {
  final BlobEntry blob;
  final IntroducingCommit? commit;

  const BigBlob(this.blob, this.commit);

  Map<String, dynamic> toJson() => {
    'blob': blob.toJson(),
    if (commit != null) 'commit': commit!.toJson(),
  };

  factory BigBlob.fromJson(Map<String, dynamic> j) => BigBlob(
    BlobEntry.fromJson(j['blob'] as Map<String, dynamic>),
    j['commit'] == null
        ? null
        : IntroducingCommit.fromJson(j['commit'] as Map<String, dynamic>),
  );
}

/// A finished largest-blobs scan, as cached between sessions.
class BlobScan {
  /// ISO-8601, UTC.
  final String scannedAt;

  /// [refsFingerprint] of the refs at scan time. A different one now means
  /// history has moved and the list may be out of date.
  final String fingerprint;
  final List<BigBlob> blobs;

  const BlobScan({
    required this.scannedAt,
    required this.fingerprint,
    required this.blobs,
  });

  Map<String, dynamic> toJson() => {
    'scannedAt': scannedAt,
    'fingerprint': fingerprint,
    'blobs': [for (final b in blobs) b.toJson()],
  };

  factory BlobScan.fromJson(Map<String, dynamic> j) => BlobScan(
    scannedAt: j['scannedAt'] as String,
    fingerprint: j['fingerprint'] as String,
    blobs: [
      for (final b in j['blobs'] as List)
        BigBlob.fromJson(b as Map<String, dynamic>),
    ],
  );
}

/// A digest of `for-each-ref` output. Cheap to take, and it changes whenever
/// any ref moves, which is when a cached scan may stop being true.
String refsFingerprint(String forEachRef) =>
    sha1.convert(utf8.encode(forEachRef)).toString();

/// Reflog entries `reflog expire --dry-run --verbose` says it would drop.
int countReflogExpiry(String out) => const LineSplitter()
    .convert(out)
    .where((l) => l.startsWith('would prune'))
    .length;

/// The format [parseBranchInfo] reads, for `for-each-ref refs/heads`.
const branchInfoFormat =
    '%(refname:short)%09%(committerdate:unix)%09%(upstream:track)';

/// A local branch as branch hygiene sees it.
class LocalBranchInfo {
  final String name;
  final DateTime lastCommit;

  /// The upstream it tracked no longer exists on the remote.
  final bool gone;

  const LocalBranchInfo({
    required this.name,
    required this.lastCommit,
    required this.gone,
  });
}

List<LocalBranchInfo> parseBranchInfo(String out) {
  final infos = <LocalBranchInfo>[];
  for (final line in const LineSplitter().convert(out)) {
    final f = line.split('\t');
    if (f.length < 2 || f[0].isEmpty) continue;
    final secs = int.tryParse(f[1]);
    if (secs == null) continue;
    infos.add(
      LocalBranchInfo(
        name: f[0],
        lastCommit: DateTime.fromMillisecondsSinceEpoch(
          secs * 1000,
          isUtc: true,
        ),
        gone: f.length > 2 && f[2] == '[gone]',
      ),
    );
  }
  return infos;
}

/// The branch "merged" is measured against: the remote's default branch when
/// it exists locally, else `main`, else `master`, else whatever is checked
/// out. [originHead] is `origin/HEAD` resolved to its short name.
String? pickTrunk({
  required Set<String> branches,
  required String? originHead,
  required String? current,
}) {
  if (originHead != null) {
    final slash = originHead.indexOf('/');
    final name = slash < 0 ? originHead : originHead.substring(slash + 1);
    if (branches.contains(name)) return name;
  }
  for (final name in const ['main', 'master']) {
    if (branches.contains(name)) return name;
  }
  return current;
}

/// Branches older than this without a merge are offered as stale.
const staleBranchAge = Duration(days: 90);

/// A local branch offered for clean-up.
class HygieneBranch {
  final String name;
  final DateTime lastCommit;
  final bool merged;
  final bool gone;

  /// The worktree that has the branch checked out. Such a branch cannot be
  /// deleted, so it is listed but not offered.
  final String? heldBy;

  const HygieneBranch({
    required this.name,
    required this.lastCommit,
    required this.merged,
    required this.gone,
    this.heldBy,
  });

  bool get selectable => heldBy == null;

  /// Unmerged work: `branch -d` refuses it, so deleting takes `-D`.
  bool get needsForce => !merged;
}

/// Merged branches first, then stale ones (old, or tracking an upstream that
/// is gone), each group by name. The trunk and the current branch are never
/// offered.
List<HygieneBranch> classifyBranches({
  required List<LocalBranchInfo> infos,
  required Set<String> merged,
  required String? trunk,
  required String? current,
  required Map<String, String> heldBy,
  required DateTime now,
  Duration staleAfter = staleBranchAge,
}) {
  final done = <HygieneBranch>[];
  final stale = <HygieneBranch>[];
  for (final i in infos) {
    if (i.name == trunk || i.name == current) continue;
    final isMerged = merged.contains(i.name);
    final old = now.difference(i.lastCommit) > staleAfter;
    if (!isMerged && !old && !i.gone) continue;
    (isMerged ? done : stale).add(
      HygieneBranch(
        name: i.name,
        lastCommit: i.lastCommit,
        merged: isMerged,
        gone: i.gone,
        heldBy: heldBy[i.name],
      ),
    );
  }
  int byName(HygieneBranch a, HygieneBranch b) => a.name.compareTo(b.name);
  return [...done..sort(byName), ...stale..sort(byName)];
}

/// Sizes for people: bytes below a KiB, one decimal above.
String formatBytes(int bytes) {
  const units = ['KB', 'MB', 'GB', 'TB'];
  if (bytes < 1024) return '$bytes B';
  var v = bytes / 1024;
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(1)} ${units[u]}';
}

/// Bytes a git directory holds, split by what they are.
class GitDirSize {
  final int packBytes;
  final int looseBytes;
  final int lfsBytes;
  final int otherBytes;

  const GitDirSize({
    this.packBytes = 0,
    this.looseBytes = 0,
    this.lfsBytes = 0,
    this.otherBytes = 0,
  });

  int get totalBytes => packBytes + looseBytes + lfsBytes + otherBytes;
}

final _looseDir = RegExp(r'^objects/[0-9a-f]{2}/');

/// Walks [gitDir] and buckets every file's size. Symlinks are not followed,
/// so a shared object store linked in is not counted twice. A missing
/// directory measures as empty.
Future<GitDirSize> measureGitDir(String gitDir) async {
  final root = Directory(gitDir);
  if (!await root.exists()) return const GitDirSize();
  var pack = 0, loose = 0, lfs = 0, other = 0;
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final int size;
    try {
      size = await e.length();
    } on FileSystemException {
      continue; // removed mid-walk, e.g. by a concurrent gc
    }
    final rel = p.relative(e.path, from: gitDir).replaceAll('\\', '/');
    if (rel.startsWith('objects/pack/')) {
      pack += size;
    } else if (_looseDir.hasMatch(rel)) {
      loose += size;
    } else if (rel.startsWith('lfs/')) {
      lfs += size;
    } else {
      other += size;
    }
  }
  return GitDirSize(
    packBytes: pack,
    looseBytes: loose,
    lfsBytes: lfs,
    otherBytes: other,
  );
}

/// [measureGitDir] on a background isolate: a repository with many loose
/// objects is tens of thousands of stat calls.
Future<GitDirSize> measureGitDirOffThread(String gitDir) =>
    Isolate.run(() => measureGitDir(gitDir));

/// Branch clean-up candidates and the branch they were measured against.
class BranchHygiene {
  final String? trunk;
  final List<HygieneBranch> branches;

  const BranchHygiene({required this.trunk, required this.branches});
}

/// Listings above this size are scanned on a background isolate. Below it,
/// copying the listing there costs more than the scan.
const _offThreadBatchChars = 1 << 20;

/// The read side of the maintenance panel. Nothing here changes the
/// repository.
class MaintenanceReader {
  final GitService git;
  final String repoPath;

  MaintenanceReader(this.git, this.repoPath);

  /// Each step of a largest-blobs scan walks every object in the repository,
  /// which on a large one runs far past the ordinary default.
  static const scanTimeout = Duration(minutes: 10);

  Future<GitResult> _run(
    List<String> args, {
    Duration? timeout,
    GitCancel? cancel,
  }) => git.run(args, repoPath: repoPath, timeout: timeout, cancel: cancel);

  /// For a read that walks every reflog or ref rather than a handful of
  /// files, which can outrun the ordinary default on a large repository.
  static const slowReadTimeout = Duration(seconds: 60);

  Future<String> _out(
    List<String> args,
    String what, {
    Duration? timeout,
  }) async {
    final r = await _run(args, timeout: timeout);
    if (!r.ok) throw GitException(what, r);
    return r.stdout;
  }

  /// Where objects actually live. A linked worktree answers with its main
  /// repository's git dir, which is what its storage is.
  Future<String> commonGitDir() async {
    final dir = (await _out([
      'rev-parse',
      '--git-common-dir',
    ], 'git rev-parse --git-common-dir')).trim();
    return p.isAbsolute(dir) ? dir : p.normalize(p.join(repoPath, dir));
  }

  Future<CountObjects> countObjects() async => parseCountObjects(
    await _out(['count-objects', '-v'], 'git count-objects'),
  );

  /// How many reflog entries the next gc would expire. No `--expire` is
  /// passed, so the user's own `gc.reflogExpire*` settings decide.
  Future<int> reflogExpiryCount() async => countReflogExpiry(
    await _out(
      ['reflog', 'expire', '--all', '--dry-run', '--verbose'],
      'git reflog expire --dry-run',
      timeout: slowReadTimeout,
    ),
  );

  /// [heldBy] maps branch names to the worktree holding them.
  Future<BranchHygiene> branchHygiene({
    required DateTime now,
    required Map<String, String> heldBy,
  }) async {
    final results = await Future.wait([
      _run(['for-each-ref', '--format=$branchInfoFormat', 'refs/heads']),
      _run(['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD']),
      _run(['branch', '--show-current']),
    ]);
    if (!results[0].ok) {
      throw GitException('git for-each-ref refs/heads', results[0]);
    }
    final infos = parseBranchInfo(results[0].stdout);
    final current = results[2].out.isEmpty ? null : results[2].out;
    final trunk = pickTrunk(
      branches: {for (final i in infos) i.name},
      originHead: results[1].ok && results[1].out.isNotEmpty
          ? results[1].out
          : null,
      current: current,
    );
    var merged = const <String>{};
    if (trunk != null) {
      final r = await _run([
        'for-each-ref',
        '--merged=$trunk',
        '--format=%(refname:short)',
        'refs/heads',
      ]);
      if (r.ok) merged = const LineSplitter().convert(r.stdout).toSet();
    }
    return BranchHygiene(
      trunk: trunk,
      branches: classifyBranches(
        infos: infos,
        merged: merged,
        trunk: trunk,
        current: current,
        heldBy: heldBy,
        now: now,
      ),
    );
  }

  Future<String> currentRefsFingerprint() async => refsFingerprint(
    await _out([
      'for-each-ref',
      '--format=%(objectname) %(refname)',
    ], 'git for-each-ref'),
  );

  /// The [top] largest blobs anywhere in history, each with the commit that
  /// introduced it. Every step takes [cancel], so the scan can be abandoned
  /// part way.
  Future<BlobScan> scanBlobs({
    required int top,
    required DateTime now,
    GitCancel? cancel,
  }) async {
    final fingerprint = await currentRefsFingerprint();
    Future<String> step(List<String> args, String what) async {
      final r = await _run(args, timeout: scanTimeout, cancel: cancel);
      if (!r.ok) throw GitException(what, r);
      return r.stdout;
    }

    final batch = await step([
      'cat-file',
      '--batch-all-objects',
      '--batch-check=$allObjectsFormat',
    ], 'git cat-file --batch-all-objects');
    final largest = batch.length > _offThreadBatchChars
        ? await Isolate.run(() => topBlobs(batch, top))
        : topBlobs(batch, top);
    final blobs = await Future.wait([
      for (final b in largest)
        step([
          'log',
          '--all',
          '--reverse',
          '--format=$blobOriginFormat',
          '--name-only',
          '--find-object=${b.sha}',
        ], 'git log --find-object').then((out) {
          final origin = parseBlobOrigin(out);
          return BigBlob(
            BlobEntry(sha: b.sha, size: b.size, path: origin.path),
            origin.commit,
          );
        }),
    ]);
    return BlobScan(
      scannedAt: now.toUtc().toIso8601String(),
      fingerprint: fingerprint,
      blobs: blobs,
    );
  }
}
