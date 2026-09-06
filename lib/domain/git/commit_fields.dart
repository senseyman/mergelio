/// Shared decoding of the commit header fields git writes under a
/// `--pretty=format:` template, used by every reader that parses a log record.
library;

const _avatarPalette = <int>[
  0xFF6C8CFF,
  0xFFF5C451,
  0xFF3DD68C,
  0xFFEB6F92,
  0xFF9D7CFF,
  0xFF4CC9F0,
  0xFFF08C4C,
  0xFF57C7A0,
];

/// Deterministic author avatar colour (ARGB) for [email], so the same author
/// keeps one colour across every view that draws them.
int avatarFor(String email) {
  var h = 0;
  for (final c in email.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

/// The trailing UTC offset of an ISO-8601 stamp (`%aI` always writes one,
/// down to `+00:00`). `DateTime.parse` folds the offset away into a UTC
/// instant, so it has to be read off the text before it is lost. Null when
/// the stamp carries no offset at all.
Duration? isoOffset(String s) {
  final m = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final d = Duration(hours: int.parse(m[2]!), minutes: int.parse(m[3]!));
  return m[1] == '-' ? -d : d;
}
