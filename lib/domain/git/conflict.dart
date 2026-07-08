/// How a single conflict hunk is resolved.
enum Resolution { ours, theirs, both, custom }

/// A parsed piece of a conflicted file: either unchanged [ContextBlock] lines
/// or a [ConflictHunk] with the two sides.
sealed class ConflictPart {
  const ConflictPart();
}

class ContextBlock extends ConflictPart {
  final List<String> lines;
  ContextBlock(this.lines);
}

class ConflictHunk extends ConflictPart {
  final List<String> ours;
  final List<String> theirs;
  ConflictHunk({required this.ours, required this.theirs});
}

final _start = RegExp(r'^<{7}');
final _base = RegExp(r'^\|{7}'); // diff3 "||||||| base" marker
final _sep = RegExp(r'^={7}');
final _end = RegExp(r'^>{7}');

bool hasConflictMarkers(String content) =>
    content.split('\n').any((l) => _start.hasMatch(l));

/// Splits a conflicted file's [content] into ordered context blocks and
/// conflict hunks. Trailing newline handling: a final empty line from the split
/// is dropped so re-emitting round-trips.
List<ConflictPart> parseConflicts(String content) {
  final lines = content.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  final parts = <ConflictPart>[];
  var context = <String>[];
  void flushContext() {
    if (context.isNotEmpty) {
      parts.add(ContextBlock(context));
      context = [];
    }
  }

  var i = 0;
  while (i < lines.length) {
    if (_start.hasMatch(lines[i])) {
      flushContext();
      final ours = <String>[], theirs = <String>[];
      i++;
      // "ours" ends at ======= (merge style) or ||||||| (diff3 style).
      while (i < lines.length &&
          !_sep.hasMatch(lines[i]) &&
          !_base.hasMatch(lines[i])) {
        ours.add(lines[i++]);
      }
      // Skip the diff3 base section, if present, up to =======.
      if (i < lines.length && _base.hasMatch(lines[i])) {
        while (i < lines.length && !_sep.hasMatch(lines[i])) {
          i++;
        }
      }
      i++; // skip =======
      while (i < lines.length && !_end.hasMatch(lines[i])) {
        theirs.add(lines[i++]);
      }
      i++; // skip >>>>>>>
      parts.add(ConflictHunk(ours: ours, theirs: theirs));
    } else {
      context.add(lines[i++]);
    }
  }
  flushContext();
  return parts;
}

/// Renders [parts] to a file body. Each hunk index in [resolutions] is applied;
/// a hunk with no resolution re-emits its conflict markers (still unresolved).
/// [custom] supplies the replacement lines for [Resolution.custom] hunks.
String resolveConflicts(
  List<ConflictPart> parts,
  Map<int, Resolution> resolutions, {
  Map<int, List<String>> custom = const {},
}) {
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part is ContextBlock) {
      out.addAll(part.lines);
    } else if (part is ConflictHunk) {
      switch (resolutions[i]) {
        case Resolution.ours:
          out.addAll(part.ours);
        case Resolution.theirs:
          out.addAll(part.theirs);
        case Resolution.both:
          out
            ..addAll(part.ours)
            ..addAll(part.theirs);
        case Resolution.custom:
          out.addAll(custom[i] ?? const []);
        case null:
          out
            ..add('<<<<<<< HEAD')
            ..addAll(part.ours)
            ..add('=======')
            ..addAll(part.theirs)
            ..add('>>>>>>> incoming');
      }
    }
  }
  return '${out.join('\n')}\n';
}
