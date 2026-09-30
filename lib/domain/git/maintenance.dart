import 'dart:convert';

import 'package:crypto/crypto.dart';

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

/// The format [parseBlobBatch] reads, handed to `cat-file --batch-check`.
/// `%(rest)` carries the path `rev-list --objects` printed after the sha.
const blobBatchFormat = '%(objecttype) %(objectname) %(objectsize) %(rest)';

/// Blobs from `rev-list --objects --all | cat-file --batch-check`. rev-list
/// can name one blob at several paths; the first is kept, since which one is
/// "the" path of shared content is arbitrary anyway.
List<BlobEntry> parseBlobBatch(String out) {
  final seen = <String>{};
  final blobs = <BlobEntry>[];
  for (final line in const LineSplitter().convert(out)) {
    if (!line.startsWith('blob ')) continue;
    final shaEnd = line.indexOf(' ', 5);
    if (shaEnd < 0) continue;
    final sizeEnd = line.indexOf(' ', shaEnd + 1);
    final size = int.tryParse(
      line.substring(shaEnd + 1, sizeEnd < 0 ? line.length : sizeEnd),
    );
    if (size == null) continue;
    final sha = line.substring(5, shaEnd);
    if (!seen.add(sha)) continue;
    blobs.add(
      BlobEntry(
        sha: sha,
        size: size,
        path: sizeEnd < 0 ? '' : line.substring(sizeEnd + 1),
      ),
    );
  }
  return blobs;
}

/// The [n] largest blobs in [batch], largest first. Equal sizes order by path
/// so a rescan of the same history lists them the same way.
List<BlobEntry> topBlobs(String batch, int n) {
  final blobs = parseBlobBatch(batch)
    ..sort((a, b) {
      final bySize = b.size.compareTo(a.size);
      return bySize != 0 ? bySize : a.path.compareTo(b.path);
    });
  return blobs.take(n).toList();
}

/// The log format [parseIntroducingCommit] reads.
const introducingCommitFormat = '%H%x1f%h%x1f%aI%x1f%s';

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

/// First line of `log --reverse --find-object=<sha>`: the oldest commit that
/// touched the blob, which is the one that added it.
IntroducingCommit? parseIntroducingCommit(String out) {
  final line = const LineSplitter().convert(out).firstOrNull;
  if (line == null) return null;
  final f = line.split('\x1f');
  if (f.length < 4) return null;
  return IntroducingCommit(
    sha: f[0],
    shortSha: f[1],
    date: f[2],
    subject: f.sublist(3).join('\x1f'),
  );
}

/// A large blob and where it came from. [commit] is null when no commit on
/// any ref could be found for it.
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
