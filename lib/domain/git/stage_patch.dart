import 'diff.dart';

/// The set of change-line indexes to stage together when the gutter beside
/// line [index] is clicked. A modified line (a deletion paired with the
/// addition that replaces it) stages both sides, otherwise the index would gain
/// a duplicate line instead of the intended replacement. A pure addition or
/// deletion stages alone. Context lines return an empty set.
Set<int> changeLineGroup(List<DiffLine> lines, int index) {
  if (lines[index].type == DiffLineType.context) return {};

  // Expand to the contiguous change block around [index].
  var start = index, end = index;
  while (start > 0 && lines[start - 1].type != DiffLineType.context) {
    start--;
  }
  while (end + 1 < lines.length &&
      lines[end + 1].type != DiffLineType.context) {
    end++;
  }

  // Within a block git lists deletions first, then additions; pair them by
  // position.
  final dels = <int>[], adds = <int>[];
  for (var i = start; i <= end; i++) {
    (lines[i].type == DiffLineType.del ? dels : adds).add(i);
  }

  final asDel = dels.indexOf(index);
  if (asDel >= 0) {
    return {index, if (asDel < adds.length) adds[asDel]};
  }
  final asAdd = adds.indexOf(index);
  return {index, if (asAdd < dels.length) dels[asAdd]};
}

/// Builds a minimal unified patch that `git apply --cached` can apply to stage
/// (or, with `--reverse`, unstage) a selection within one hunk of [file].
///
/// [lineIndexes] selects change lines (by their index within the hunk); null
/// selects the whole hunk. Unselected additions are dropped and unselected
/// deletions become context, so the patch expresses exactly the chosen change.
/// Returns null when nothing in the hunk is selected.
String? buildStagePatch(FileDiff file, int hunkIndex, {Set<int>? lineIndexes}) {
  final hunk = file.hunks[hunkIndex];
  bool selected(int i, DiffLine l) =>
      l.type != DiffLineType.context &&
      (lineIndexes == null || lineIndexes.contains(i));

  if (!hunk.lines.asMap().entries.any((e) => selected(e.key, e.value))) {
    return null;
  }

  final body = <String>[];
  var oldCount = 0, newCount = 0;
  for (var i = 0; i < hunk.lines.length; i++) {
    final l = hunk.lines[i];
    var emitted = false;
    switch (l.type) {
      case DiffLineType.context:
        body.add(' ${l.text}');
        oldCount++;
        newCount++;
        emitted = true;
      case DiffLineType.add:
        if (selected(i, l)) {
          body.add('+${l.text}');
          newCount++;
          emitted = true;
        }
      // Unselected additions are omitted entirely.
      case DiffLineType.del:
        if (selected(i, l)) {
          body.add('-${l.text}');
          oldCount++;
          emitted = true;
        } else {
          // Keep the line: it stays in the index, so it is context on both
          // sides.
          body.add(' ${l.text}');
          oldCount++;
          newCount++;
          emitted = true;
        }
    }
    if (emitted && l.noNewline) body.add(r'\ No newline at end of file');
  }

  final header =
      '@@ -${hunk.oldStart},$oldCount +${hunk.newStart},$newCount @@';
  final old = file.oldPath ?? file.path;
  return 'diff --git a/$old b/${file.path}\n'
      '--- a/$old\n'
      '+++ b/${file.path}\n'
      '$header\n'
      '${body.join('\n')}\n';
}
