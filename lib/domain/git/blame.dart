/// How far blame looks for where a line really came from. git only counts a
/// line as moved once it carries enough letters and digits, so short lines
/// stay with the commit that moved them.
enum BlameMoves {
  off,

  /// `-M`: a block moved or copied within the file keeps its author.
  withinFile,

  /// `-C`: lines moved in from another file changed in the same commit keep
  /// theirs too. Implies [withinFile].
  acrossFiles,
}

/// An ignore-revs file found for blame, with the first line git would refuse
/// in it — empty when the file could not be read at all — or null when git
/// takes the whole file.
typedef BlameRevsFile = ({String path, String? invalid});

/// The first line of an ignore-revs file that git would refuse, or null when
/// it would take the whole file. git reads a line as a full object name
/// ([hexLength] hex digits, either case) once anything after `#` and the
/// surrounding whitespace are gone, and skips what is left blank. One bad line
/// — an abbreviated sha is enough — fails the whole blame.
String? firstInvalidIgnoreRev(String content, {int hexLength = 40}) {
  final name = RegExp('^[0-9a-fA-F]{$hexLength}\$');
  for (final raw in content.split('\n')) {
    final hash = raw.indexOf('#');
    final line = (hash < 0 ? raw : raw.substring(0, hash)).trim();
    if (line.isNotEmpty && !name.hasMatch(line)) return line;
  }
  return null;
}

/// One blamed line: which commit and author last touched it, and the text.
class BlameLine {
  final String sha;
  final String author;
  final String content;
  const BlameLine({
    required this.sha,
    required this.author,
    required this.content,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

final _header = RegExp(r'^([0-9a-f]{7,64}) ');

/// Parses `git blame --line-porcelain` output. Each line's block starts with a
/// sha header, carries an `author` field, and ends with a tab-prefixed content
/// line — which is the actual source text for that line.
List<BlameLine> parseBlame(String raw) {
  final out = <BlameLine>[];
  String sha = '', author = '';
  for (final line in raw.split('\n')) {
    final h = _header.firstMatch(line);
    if (h != null && !line.startsWith('\t')) {
      sha = h.group(1)!;
    } else if (line.startsWith('author ')) {
      author = line.substring('author '.length);
    } else if (line.startsWith('\t')) {
      out.add(BlameLine(sha: sha, author: author, content: line.substring(1)));
    }
  }
  return out;
}
