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
