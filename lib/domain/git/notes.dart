/// Which commits carry a git note, as `git notes list` reports it.
library;

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
