import 'package:characters/characters.dart';

import '../forge/models.dart';

/// A commit message split the way the UI edits it: a one-line summary and
/// everything below it.
typedef CommitMessageParts = ({String summary, String description});

/// Splits a raw git message (`%B`) into its summary line and description.
/// Line endings are normalised to `\n` so a message authored on Windows edits
/// the same as any other, and the description is trimmed — git's own blank
/// separator line is not part of what the user typed.
CommitMessageParts splitCommitMessage(String message) {
  final text = message.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final nl = text.indexOf('\n');
  if (nl == -1) return (summary: text.trim(), description: '');
  return (
    summary: text.substring(0, nl).trim(),
    description: text.substring(nl + 1).trim(),
  );
}

/// Rebuilds a raw git message from its edited parts, reinstating the blank
/// separator line git expects between subject and body.
String joinCommitMessage(String summary, String description) {
  final s = summary.trim();
  final d = description.trim();
  return d.isEmpty ? s : '$s\n\n$d';
}

// --- Templates ---------------------------------------------------------------

/// The marker line git writes above the diff it appends to a verbose message;
/// nothing below it is part of the message.
const _scissors = '------------------------ >8 ------------------------';

/// What git's `strip` cleanup leaves of [text]: comment lines (those starting
/// with [commentChar]) and everything below the scissors line removed,
/// trailing whitespace dropped, blank runs collapsed and the ends trimmed.
/// The composer commits with `-m`, where git strips nothing, so a template's
/// guidance has to come off here.
String stripCommentLines(String text, {String commentChar = '#'}) {
  final lines = <String>[];
  for (final line in _lines(text)) {
    if (line.startsWith('$commentChar $_scissors')) break;
    if (line.startsWith(commentChar)) continue;
    lines.add(line);
  }
  return _tidy(lines);
}

/// Whether [message] is still exactly what [template] offered — git refuses
/// such a commit when it runs the editor, and the composer does the same. An
/// empty template matches nothing.
bool isUntouchedTemplate(
  String message,
  String template, {
  String commentChar = '#',
}) {
  final t = stripCommentLines(template, commentChar: commentChar);
  return t.isNotEmpty && _tidy(_lines(message)) == t;
}

List<String> _lines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

String _tidy(List<String> lines) {
  final out = <String>[];
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

// --- Conventional Commits ----------------------------------------------------

/// The types the composer's picker offers, in the order it lists them.
const kConventionalTypes = [
  'feat',
  'fix',
  'docs',
  'style',
  'refactor',
  'perf',
  'test',
  'build',
  'ci',
  'chore',
  'revert',
];

/// A subject split into its Conventional Commits parts. An empty [type]
/// means the subject is not conventional and [description] is all of it.
typedef ConventionalSubject = ({
  String type,
  String scope,
  bool breaking,
  String description,
});

/// `type(scope)!: description`, leaving out what is not set. With no type
/// the description is the whole subject — scope and breaking mean nothing
/// without one.
String formatConventionalSubject(ConventionalSubject s) {
  final description = s.description.trim();
  if (s.type.isEmpty) return description;
  final scope = s.scope.trim();
  return '${s.type}'
      '${scope.isEmpty ? '' : '($scope)'}'
      '${s.breaking ? '!' : ''}: $description';
}

final _conventional = RegExp(r'^([a-z]+)(?:\(([^()\n]*)\))?(!)?: (.*)$');

/// The parts of [subject] when it is conventional and its type is one the
/// picker offers, spelled as the picker spells it; null otherwise, so the
/// caller keeps the text as typed — `Feat:` is not quietly rewritten.
ConventionalSubject? parseConventionalSubject(String subject) {
  final m = _conventional.firstMatch(subject.trim());
  if (m == null) return null;
  final type = m[1]!;
  if (!kConventionalTypes.contains(type)) return null;
  return (
    type: type,
    scope: (m[2] ?? '').trim(),
    breaking: m[3] != null,
    description: m[4]!.trim(),
  );
}

// --- Length and wrapping -----------------------------------------------------

/// Length of a subject as the reader counts it: user-perceived characters,
/// so an accented letter or a joined emoji is one, not the several UTF-16
/// units or code points a Dart string is measured in.
int subjectLength(String subject) => subject.characters.length;

final _listItem = RegExp(r'^([-*+]|\d+[.)])\s');
final _trailerLine = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*: \S');

/// Rewraps the prose paragraphs of a commit body to [width] columns. Lines
/// whose shape carries meaning are left exactly as written: list items,
/// quotes, indented or fenced code and trailers. A word longer than the
/// width — a URL, usually — gets a line of its own rather than being split.
String wrapBody(String text, int width) {
  final out = <String>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    var line = '';
    for (final word in paragraph.join(' ').split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (line.isEmpty) {
        line = word;
      } else if (subjectLength(line) + 1 + subjectLength(word) <= width) {
        line = '$line $word';
      } else {
        out.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) out.add(line);
    paragraph.clear();
  }

  var fenced = false;
  for (final line in _lines(text)) {
    final fence = line.trimLeft().startsWith('```');
    final verbatim =
        fenced ||
        fence ||
        line.trim().isEmpty ||
        line.startsWith(RegExp(r'\s')) ||
        line.startsWith('>') ||
        _listItem.hasMatch(line) ||
        _trailerLine.hasMatch(line);
    if (fence) fenced = !fenced;
    if (verbatim) {
      flush();
      out.add(line);
    } else {
      paragraph.add(line.trim());
    }
  }
  flush();
  return out.join('\n');
}

// --- Trailers ----------------------------------------------------------------

/// One `Key: value` line of the trailer block at the end of a message.
typedef CommitTrailer = ({String key, String value});

/// A comma-separated field as its trimmed, non-empty entries.
List<String> splitList(String text) => [
  for (final s in text.split(','))
    if (s.trim().isNotEmpty) s.trim(),
];

/// A bare number is the forge's issue number and gets its `#`; anything else
/// (`#12`, `JIRA-4`) is already a reference and is kept.
String normaliseIssueRef(String ref) {
  final r = ref.trim();
  return RegExp(r'^\d+$').hasMatch(r) ? '#$r' : r;
}

/// The trailers the composer's fields add, in the order they are written.
List<CommitTrailer> buildTrailers({
  List<String> refs = const [],
  List<String> fixes = const [],
  List<String> coauthors = const [],
}) => [
  for (final r in refs) (key: 'Refs', value: normaliseIssueRef(r)),
  for (final f in fixes) (key: 'Fixes', value: normaliseIssueRef(f)),
  for (final c in coauthors) (key: 'Co-authored-by', value: c.trim()),
];

/// The full message: subject, body, then [trailers] as one block. git only
/// reads trailers from the last paragraph, so when the body already ends in
/// trailers of its own the new ones join that paragraph instead of starting
/// a second one.
String buildCommitMessage(
  String subject,
  String description, {
  List<CommitTrailer> trailers = const [],
}) {
  final message = joinCommitMessage(subject, description);
  if (trailers.isEmpty) return message;
  final block = [for (final t in trailers) '${t.key}: ${t.value}'].join('\n');
  final d = description.trim();
  final last = d.isEmpty ? const <String>[] : d.split('\n\n').last.split('\n');
  final joins = last.isNotEmpty && last.every(_trailerLine.hasMatch);
  return joins ? '$message\n$block' : '$message\n\n$block';
}

// --- Recall and completion ---------------------------------------------------

/// [recent] with [message] moved to the front, any earlier copy dropped and
/// the list cut to [cap].
List<String> pushRecent(List<String> recent, String message, {int cap = 10}) {
  final m = message.trim();
  if (m.isEmpty) return recent;
  return [m, ...recent.where((r) => r != m)].take(cap).toList();
}

/// The entry of a comma-separated field the caret is completing: whatever
/// follows the last comma.
String currentToken(String text) {
  final i = text.lastIndexOf(',');
  return text.substring(i + 1).trim();
}

/// [text] with its last entry replaced by [token].
String replaceCurrentToken(String text, String token) {
  final i = text.lastIndexOf(',');
  return i < 0 ? token : '${text.substring(0, i + 1)} $token';
}

/// The issues a typed [query] can complete to: by number prefix when it is a
/// number (`#` optional), otherwise by title.
List<Issue> matchIssues(List<Issue> issues, String query) {
  final q = query.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
  if (q.isEmpty) return issues;
  if (RegExp(r'^\d+$').hasMatch(q)) {
    return [
      for (final i in issues)
        if ('${i.number}'.startsWith(q)) i,
    ];
  }
  return [
    for (final i in issues)
      if (i.title.toLowerCase().contains(q)) i,
  ];
}
