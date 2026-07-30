import 'models.dart';

enum DiffLineType { context, add, del }

/// A word-level segment of a diff line. [changed] marks the token as part of
/// the intra-line change (highlighted); false is unchanged surrounding text.
class DiffSeg {
  final String text;
  final bool changed;
  const DiffSeg(this.text, {this.changed = false});
}

/// One line of a hunk. [oldNo]/[newNo] are 1-based line numbers, null on the
/// side where the line does not exist. [words] is set only when a word-level
/// diff was computed for a modified line.
class DiffLine {
  final DiffLineType type;
  final int? oldNo;
  final int? newNo;
  final String text;
  final List<DiffSeg>? words;

  /// True when git reported "\ No newline at end of file" for this line — the
  /// patch must reproduce that marker or `git apply` rejects it.
  final bool noNewline;

  const DiffLine({
    required this.type,
    this.oldNo,
    this.newNo,
    required this.text,
    this.words,
    this.noNewline = false,
  });

  DiffLine withWords(List<DiffSeg> w) => DiffLine(
    type: type,
    oldNo: oldNo,
    newNo: newNo,
    text: text,
    words: w,
    noNewline: noNewline,
  );

  DiffLine markNoNewline() => DiffLine(
    type: type,
    oldNo: oldNo,
    newNo: newNo,
    text: text,
    words: words,
    noNewline: true,
  );
}

class DiffHunk {
  final String header;
  final int oldStart;
  final int newStart;
  final List<DiffLine> lines;
  const DiffHunk({
    required this.header,
    required this.oldStart,
    required this.newStart,
    required this.lines,
  });
}

class FileDiff {
  final String path;
  final String? oldPath;
  final GitChange status;
  final bool binary;
  final List<DiffHunk> hunks;
  const FileDiff({
    required this.path,
    this.oldPath,
    required this.status,
    this.binary = false,
    this.hunks = const [],
  });
}

/// Word-level diff of a modified line pair. Splits each side into tokens
/// (runs of word characters, or single other characters) and marks the tokens
/// that differ via a longest-common-subsequence match. Returns segments for the
/// deleted then the added side; concatenating each side's [DiffSeg.text]
/// reproduces the original line.
(List<DiffSeg>, List<DiffSeg>) diffWords(String del, String add) {
  final a = _tokenize(del);
  final b = _tokenize(add);

  // LCS table over tokens.
  final n = a.length, m = b.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final delSegs = <DiffSeg>[], addSegs = <DiffSeg>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      delSegs.add(DiffSeg(a[i]));
      addSegs.add(DiffSeg(b[j]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      delSegs.add(_seg(a[i++]));
    } else {
      addSegs.add(_seg(b[j++]));
    }
  }
  while (i < n) {
    delSegs.add(_seg(a[i++]));
  }
  while (j < m) {
    addSegs.add(_seg(b[j++]));
  }
  return (_coalesce(delSegs), _coalesce(addSegs));
}

/// A changed token, except whitespace-only tokens stay unmarked — a moved
/// space carries no visible highlight and only adds rendering noise.
DiffSeg _seg(String tok) => DiffSeg(tok, changed: tok.trim().isNotEmpty);

/// Computes word-level segments for modified lines within a hunk: each maximal
/// run of deleted lines directly followed by a run of added lines of the same
/// length is paired line-for-line. Runs of unequal length (pure add / delete /
/// block replacement) are left without segments.
/// Combined del+add length above which word-level diffing is skipped.
const _wordDiffMaxLen = 4000;

List<DiffLine> annotateWords(List<DiffLine> lines) {
  final out = List<DiffLine>.of(lines);
  var i = 0;
  while (i < out.length) {
    if (out[i].type != DiffLineType.del) {
      i++;
      continue;
    }
    var delEnd = i;
    while (delEnd < out.length && out[delEnd].type == DiffLineType.del) {
      delEnd++;
    }
    var addEnd = delEnd;
    while (addEnd < out.length && out[addEnd].type == DiffLineType.add) {
      addEnd++;
    }
    final dels = delEnd - i, adds = addEnd - delEnd;
    if (dels > 0 && dels == adds) {
      for (var k = 0; k < dels; k++) {
        final d = out[i + k], a = out[delEnd + k];
        // The token LCS is O(n·m); skip word-level for very long lines
        // (e.g. minified bundles) so opening the diff stays responsive.
        if (d.text.length + a.text.length > _wordDiffMaxLen) continue;
        final (dw, aw) = diffWords(d.text, a.text);
        out[i + k] = d.withWords(dw);
        out[delEnd + k] = a.withWords(aw);
      }
    }
    i = addEnd > i ? addEnd : i + 1;
  }
  return out;
}

final _word = RegExp(r'[A-Za-z0-9_]');

List<String> _tokenize(String s) {
  final out = <String>[];
  var i = 0;
  while (i < s.length) {
    if (_word.hasMatch(s[i])) {
      final start = i;
      while (i < s.length && _word.hasMatch(s[i])) {
        i++;
      }
      out.add(s.substring(start, i));
    } else {
      out.add(s[i++]);
    }
  }
  return out;
}

/// Merges adjacent segments of the same changed-ness so rendering draws fewer
/// spans.
List<DiffSeg> _coalesce(List<DiffSeg> segs) {
  final out = <DiffSeg>[];
  for (final s in segs) {
    if (out.isNotEmpty && out.last.changed == s.changed) {
      out[out.length - 1] = DiffSeg(out.last.text + s.text, changed: s.changed);
    } else {
      out.add(s);
    }
  }
  return out;
}

enum SyntaxKind { plain, keyword, string, number, comment }

class SyntaxToken {
  final String text;
  final SyntaxKind kind;
  const SyntaxToken(this.text, this.kind);
}

/// A small language-agnostic set of keywords common across the languages this
/// tool is likely to show. Not exhaustive by design — the highlighter is a
/// readability aid, not a parser.
const _keywords = {
  'abstract',
  'as',
  'async',
  'await',
  'bool',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'def',
  'default',
  'do',
  'double',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'false',
  'final',
  'finally',
  'float',
  'for',
  'from',
  'func',
  'function',
  'if',
  'implements',
  'import',
  'in',
  'int',
  'interface',
  'let',
  'new',
  'null',
  'package',
  'private',
  'protected',
  'public',
  'return',
  'self',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

final _ident = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
final _numStart = RegExp(r'[0-9]');
// Hex literal, or an integer/decimal with an optional single fractional part.
final _numRe = RegExp(r'0[xX][0-9a-fA-F]+|[0-9]+(?:\.[0-9]+)?');

/// Splits one source line into coloured tokens: keywords, strings, numbers,
/// line comments, and plain text. Concatenating the tokens' text restores the
/// input exactly.
List<SyntaxToken> highlightLine(String line) {
  final out = <SyntaxToken>[];
  final buf = StringBuffer();
  void flushPlain() {
    if (buf.isNotEmpty) {
      out.add(SyntaxToken(buf.toString(), SyntaxKind.plain));
      buf.clear();
    }
  }

  var i = 0;
  while (i < line.length) {
    final c = line[i];
    final rest = line.substring(i);

    // Line comments: // … or # … ('--' is omitted: it collides with the
    // decrement operator far more often than it marks a comment).
    if (rest.startsWith('//') || rest.startsWith('#')) {
      flushPlain();
      out.add(SyntaxToken(rest, SyntaxKind.comment));
      return out;
    }

    // Strings: '...' or "..." (with backslash escapes, no line breaks).
    if (c == '"' || c == "'") {
      flushPlain();
      final quote = c;
      final start = i;
      i++;
      while (i < line.length) {
        if (line[i] == r'\' && i + 1 < line.length) {
          i += 2;
          continue;
        }
        if (line[i] == quote) {
          i++;
          break;
        }
        i++;
      }
      out.add(SyntaxToken(line.substring(start, i), SyntaxKind.string));
      continue;
    }

    // Numbers (not when glued to the end of an identifier, e.g. `x2`). A
    // trailing '.' is only consumed when a fractional digit follows, so
    // `2.toString()` keeps the number as `2`.
    final prev = buf.isEmpty ? '' : buf.toString().substring(buf.length - 1);
    if (_numStart.hasMatch(c) && !RegExp(r'[A-Za-z_]').hasMatch(prev)) {
      final m = _numRe.matchAsPrefix(rest)!;
      flushPlain();
      out.add(SyntaxToken(m.group(0)!, SyntaxKind.number));
      i += m.group(0)!.length;
      continue;
    }

    // Identifiers / keywords.
    final idm = _ident.matchAsPrefix(rest);
    if (idm != null) {
      flushPlain();
      final word = idm.group(0)!;
      out.add(
        SyntaxToken(
          word,
          _keywords.contains(word) ? SyntaxKind.keyword : SyntaxKind.plain,
        ),
      );
      i += word.length;
      continue;
    }

    buf.write(c);
    i++;
  }
  flushPlain();
  return out;
}

final _hunkHeader = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');

/// Parses `git diff` unified output into a [FileDiff] per file. Handles new /
/// deleted / renamed / binary files and standard hunks; line numbers are
/// tracked per side.
List<FileDiff> parseUnifiedDiff(String raw) {
  final out = <FileDiff>[];
  final lines = raw.split('\n');

  // Mutable accumulator for the file currently being parsed.
  String? path, oldPath, fromPath, toPath;
  var status = GitChange.modified;
  var binary = false;
  var hunks = <DiffHunk>[];
  List<DiffLine>? hunkLines;
  var oldNo = 0, newNo = 0;
  String? hunkHeader;
  var oldStart = 0, newStart = 0;

  void flushHunk() {
    if (hunkLines != null) {
      hunks.add(
        DiffHunk(
          header: hunkHeader ?? '',
          oldStart: oldStart,
          newStart: newStart,
          lines: annotateWords(hunkLines!),
        ),
      );
      hunkLines = null;
    }
  }

  void flushFile() {
    flushHunk();
    if (path != null || toPath != null) {
      out.add(
        FileDiff(
          path: toPath ?? path ?? '',
          oldPath: status == GitChange.renamed ? (fromPath ?? oldPath) : null,
          status: status,
          binary: binary,
          hunks: hunks,
        ),
      );
    }
    path = oldPath = fromPath = toPath = null;
    status = GitChange.modified;
    binary = false;
    hunks = <DiffHunk>[];
    hunkHeader = null;
  }

  for (final line in lines) {
    if (line.startsWith('diff --git ')) {
      flushFile();
      // diff --git a/<old> b/<new>
      final m = RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(line);
      if (m != null) {
        path = m.group(2);
        oldPath = m.group(1);
      }
      continue;
    }
    // A hunk header starts (or restarts) the body.
    final hh = _hunkHeader.firstMatch(line);
    if (hh != null) {
      flushHunk();
      // Guard against malformed diff output that could throw FormatException
      // on parseInt. A corrupt hunk header is skipped rather than crashing
      // the entire diff parse.
      final parsedOld = int.tryParse(hh.group(1)!);
      final parsedNew = int.tryParse(hh.group(2)!);
      if (parsedOld == null || parsedNew == null) continue;
      oldStart = parsedOld;
      newStart = parsedNew;
      oldNo = oldStart;
      newNo = newStart;
      hunkHeader = line;
      hunkLines = [];
      continue;
    }

    // Inside a hunk every line is body — including content that happens to
    // start with '---', '+++' or '\', which must not be read as file metadata.
    if (hunkLines != null) {
      if (line.startsWith(r'\')) {
        // "\ No newline at end of file" annotates the line just emitted.
        if (hunkLines!.isNotEmpty) {
          hunkLines![hunkLines!.length - 1] = hunkLines!.last.markNoNewline();
        }
        continue;
      }
      if (line.startsWith('+')) {
        hunkLines!.add(
          DiffLine(
            type: DiffLineType.add,
            newNo: newNo++,
            text: line.substring(1),
          ),
        );
      } else if (line.startsWith('-')) {
        hunkLines!.add(
          DiffLine(
            type: DiffLineType.del,
            oldNo: oldNo++,
            text: line.substring(1),
          ),
        );
      } else if (line.startsWith(' ')) {
        hunkLines!.add(
          DiffLine(
            type: DiffLineType.context,
            oldNo: oldNo++,
            newNo: newNo++,
            text: line.substring(1),
          ),
        );
      }
      continue;
    }

    // Preamble metadata (only before the first hunk of a file).
    if (line.startsWith('new file')) {
      status = GitChange.added;
      continue;
    }
    if (line.startsWith('deleted file')) {
      status = GitChange.deleted;
      continue;
    }
    if (line.startsWith('rename from ')) {
      status = GitChange.renamed;
      fromPath = line.substring('rename from '.length);
      continue;
    }
    if (line.startsWith('rename to ')) {
      status = GitChange.renamed;
      toPath = line.substring('rename to '.length);
      continue;
    }
    if (line.startsWith('Binary files')) {
      binary = true;
      continue;
    }
    if (line.startsWith('+++ ')) {
      final p = line.substring(4);
      if (p != '/dev/null') toPath = p.startsWith('b/') ? p.substring(2) : p;
      continue;
    }
    // '--- ' (old-file header), 'index …' and other preamble lines are ignored.
  }
  flushFile();
  return out;
}
