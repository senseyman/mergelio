/// Rewrites the `tag <name>` header of a raw annotated tag object (as
/// `git cat-file tag` prints it) to [newName], leaving every other byte —
/// target, tagger, date and message — as it was, so `git mktag` can store
/// the renamed copy.
///
/// Only the header block counts: a message line that happens to read
/// `tag ...` stays untouched. Throws [FormatException] when the headers carry
/// no tag name, which no object git wrote would do.
String renameTagObject(String raw, String newName) {
  final end = raw.indexOf('\n\n');
  final headers = end < 0 ? raw : raw.substring(0, end + 1);
  final match = RegExp(r'^tag [^\n]*$', multiLine: true).firstMatch(headers);
  if (match == null) {
    throw const FormatException('tag object has no tag header');
  }
  return raw.replaceRange(match.start, match.end, 'tag $newName');
}
