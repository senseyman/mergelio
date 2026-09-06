import 'commit_fields.dart';
import 'diff.dart';
import 'models.dart';

/// One step in the history of a line range: the commit that changed the range,
/// and the diff of the range as it stood in that commit.
///
/// [path] is the file's name at that point in history — `git log -L` walks the
/// range back through renames, so the oldest entries can carry an earlier name
/// than the one the range was asked for.
class LineHistoryEntry {
  final Commit commit;
  final String path;
  final List<DiffHunk> hunks;

  const LineHistoryEntry({
    required this.commit,
    required this.path,
    required this.hunks,
  });
}

/// The line range a run of picked diff lines covers, in the file's post-image
/// numbering — the numbering `git log -L` expects. Null when [lines] picks out
/// nothing inside [hunk].
///
/// Deleted lines have no post-image number, so a run made only of them is
/// anchored on the surviving line above it: the position the removed text used
/// to occupy.
(int, int)? lineRangeOfHunk(DiffHunk hunk, Iterable<int> lines) {
  final picked = lines.where((i) => i >= 0 && i < hunk.lines.length).toList();
  if (picked.isEmpty) return null;

  var lo = 0, hi = 0;
  for (final i in picked) {
    final n = hunk.lines[i].newNo;
    if (n == null) continue;
    lo = lo == 0 ? n : (n < lo ? n : lo);
    hi = n > hi ? n : hi;
  }
  if (lo != 0) return (lo, hi);

  // Deletions only: walk back to the nearest line that survived, falling back
  // to the hunk's own start when the run opens the hunk.
  var anchor = hunk.newStart;
  for (var i = picked.reduce((a, b) => a < b ? a : b) - 1; i >= 0; i--) {
    final n = hunk.lines[i].newNo;
    if (n != null) {
      anchor = n;
      break;
    }
  }
  return (anchor, anchor);
}

/// Field separator inside a record, and the NUL that opens each one.
const _fs = '\x1f';
const _rs = '\x00';

/// The `--pretty=format:` template [parseLineHistory] expects: a leading NUL,
/// then the seven header fields, then a trailing separator the patch follows.
///
/// `-L` always appends the range's patch to the record, so records cannot be
/// delimited by `-z` the way the plain log readers do it. The leading NUL gives
/// the parser a boundary the patch text cannot contain instead. The commit body
/// is left out for the same reason: it is multi-line, so it could not be told
/// apart from the patch that follows it.
const kLineHistoryFormat = '%x00%H$_fs%P$_fs%an$_fs%ae$_fs%aI$_fs%D$_fs%s$_fs';

/// Parses `git log -L<start>,<end>:<path>` output written with
/// [kLineHistoryFormat], newest commit first.
List<LineHistoryEntry> parseLineHistory(String raw) {
  final out = <LineHistoryEntry>[];
  for (final rec in raw.split(_rs)) {
    if (rec.isEmpty) continue;
    final f = rec.split(_fs);
    if (f.length < 8) continue;
    // Everything past the header is patch text, which may itself contain a
    // field separator if the source line does; put those back.
    final files = parseUnifiedDiff(f.sublist(7).join(_fs));
    out.add(
      LineHistoryEntry(
        commit: Commit(
          sha: f[0],
          parents: f[1].split(' ').where((s) => s.isNotEmpty).toList(),
          author: f[2],
          authorEmail: f[3],
          date: DateTime.parse(f[4]),
          dateOffset: isoOffset(f[4]),
          message: f[6],
          avatarValue: avatarFor(f[3]),
        ),
        path: files.isEmpty ? '' : files.first.path,
        hunks: [for (final file in files) ...file.hunks],
      ),
    );
  }
  return out;
}
