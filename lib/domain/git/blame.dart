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

final _header = RegExp(r'^([0-9a-f]{7,40}) ');

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
