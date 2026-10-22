/// Git notes: which commits carry one, and the form git stores them in.
library;

/// [text] as git stores a note: trailing whitespace off every line, runs of
/// blank lines down to one, blank lines at either end dropped. Empty means no
/// note. Comparing this, not the raw text, tells whether an edit would change
/// anything git keeps.
String normalizeNote(String text) {
  final out = <String>[];
  var blank = false;
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      blank = out.isNotEmpty;
      continue;
    }
    if (blank) out.add('');
    blank = false;
    out.add(line);
  }
  return out.join('\n');
}

/// The lines of a `<sha> <refname>` listing that name a notes ref. A note
/// write changes exactly these, so the notes index is re-read only when they
/// do. Empty when the repository has no notes at all.
String notesRefsSignature(String refListing) => [
  for (final line in refListing.split('\n'))
    if (line.contains(' refs/notes/')) line.trim(),
].join('\n');

/// Refs the graph's history walk leaves out: notes commits, and the remote
/// notes fetched aside before a merge, are bookkeeping, not history.
const notesWalkExcludes = [
  '--exclude=refs/notes/*',
  '--exclude=refs/mergelio/notes/*',
];

final _objectName = RegExp(r'^[0-9a-f]{4,64}$');

/// Parses `git notes list` output — `<note-blob> <annotated-object>` per line
/// — into annotated object → note blob. The blob changes whenever the note's
/// text does, so it doubles as the note's version. A line that is not two
/// object names is skipped.
Map<String, String> parseNoteIndex(String out) {
  final index = <String, String>{};
  for (final line in out.split('\n')) {
    final f = line.trim().split(' ');
    if (f.length != 2) continue;
    if (!_objectName.hasMatch(f[0]) || !_objectName.hasMatch(f[1])) continue;
    index[f[1]] = f[0];
  }
  return index;
}
