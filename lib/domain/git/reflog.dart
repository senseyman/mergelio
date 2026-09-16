import 'commit_fields.dart';

/// One entry of `git log -g` — where a ref pointed, and what moved it there.
///
/// [action] is the verb git recorded (`commit`, `reset`, `rebase (finish)`) and
/// [detail] the rest of its message. They arrive as one string; splitting them
/// lets the verb be shown apart from the prose, which is what makes a long
/// reflog scannable.
class ReflogEntry {
  /// Position in the log, e.g. `HEAD@{3}`. Stable only until the ref moves
  /// again, so actions address the entry by [sha], never by this.
  final String selector;
  final String sha;
  final String action;
  final String detail;
  final String author;
  final String email;
  final DateTime date;

  /// UTC offset of the machine the entry was written on; [date] alone is a
  /// bare instant. Null when git reported no offset.
  final Duration? dateOffset;

  const ReflogEntry({
    required this.selector,
    required this.sha,
    required this.action,
    this.detail = '',
    this.author = '',
    this.email = '',
    required this.date,
    this.dateOffset,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// Field and record separators. `-z` gives the record separator; the field one
/// is chosen here because no git identity or message may contain it.
const _fs = '\x1f';
const _rs = '\x00';

/// The `--pretty` argument [parseReflog] expects, kept beside the parser so
/// the field order cannot drift away from the code that reads it.
const reflogPrettyFormat = 'format:%H$_fs%gd$_fs%gs$_fs%an$_fs%ae$_fs%aI';

/// Parses `git log -g -z` records in the field order
/// `%H %gd %gs %an %ae %aI`.
///
/// A record missing fields or carrying an unparseable date is skipped rather
/// than surfaced half-empty: an interrupted git can leave a torn trailing
/// record, and a recovery list is worth less if its rows might be fiction.
List<ReflogEntry> parseReflog(String stdout) {
  final out = <ReflogEntry>[];
  for (final rec in stdout.split(_rs)) {
    final f = rec.split(_fs);
    if (f.length < 6) continue;
    final date = DateTime.tryParse(f[5]);
    if (date == null) continue;
    final subject = f[2];
    final sep = subject.indexOf(': ');
    out.add(
      ReflogEntry(
        sha: f[0],
        selector: f[1],
        action: sep < 0 ? subject : subject.substring(0, sep),
        detail: sep < 0 ? '' : subject.substring(sep + 2),
        author: f[3],
        email: f[4],
        date: date,
        dateOffset: isoOffset(f[5]),
      ),
    );
  }
  return out;
}
