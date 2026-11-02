/// Rewrites the `tag <name>` header of a raw annotated tag object (as
/// `git cat-file tag` prints it) to [newName], leaving every other byte —
/// target, tagger, date and message — as it was, so `git mktag` can store
/// the renamed copy.
///
/// Only the header block counts: a message line that happens to read
/// `tag ...` stays untouched. Throws [FormatException] when the headers carry
/// no tag name, which no object git wrote would do.
String renameTagObject(String raw, String newName) {
  final match = RegExp(
    r'^tag [^\n]*$',
    multiLine: true,
  ).firstMatch(_headers(raw));
  if (match == null) {
    throw const FormatException('tag object has no tag header');
  }
  return raw.replaceRange(match.start, match.end, 'tag $newName');
}

/// Whether the raw tag object [raw] carries a signature: a signature block
/// in the body, or a `gpgsig` header signing it under the other hash
/// algorithm.
///
/// Read from the text rather than asked of git, because git only recognises
/// SSH signatures from 2.34 on: an older git would report an SSH-signed tag
/// as unsigned, and a rewrite would void its signature.
bool isSignedTagObject(String raw) {
  if (RegExp(r'^gpgsig', multiLine: true).hasMatch(_headers(raw))) {
    return true;
  }
  final end = raw.indexOf('\n\n');
  if (end < 0) return false;
  return RegExp(
    r'^-----BEGIN (PGP SIGNATURE|PGP MESSAGE|SSH SIGNATURE|SIGNED MESSAGE)-----$',
    multiLine: true,
  ).hasMatch(raw.substring(end + 2));
}

/// The header block of [raw]: everything up to and including the newline
/// before the blank line that starts the message.
String _headers(String raw) {
  final end = raw.indexOf('\n\n');
  return end < 0 ? raw : raw.substring(0, end + 1);
}
