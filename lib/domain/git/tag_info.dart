/// Tags as the details panel shows them — who tagged, when, and what they
/// wrote — and the repository's signing setup as the create-tag dialog uses
/// it.
library;

import 'commit_fields.dart';

/// A tag on a commit. A lightweight tag is only a name: it has no tagger,
/// date or message of its own.
class TagInfo {
  final String name;
  final bool annotated;
  final String tagger;
  final String taggerEmail;

  /// Null for a lightweight tag.
  final DateTime? date;

  /// The tagger's UTC offset, so the date reads as they wrote it.
  final Duration? dateOffset;
  final String subject;
  final String body;

  const TagInfo({
    required this.name,
    required this.annotated,
    this.tagger = '',
    this.taggerEmail = '',
    this.date,
    this.dateOffset,
    this.subject = '',
    this.body = '',
  });
}

/// `for-each-ref` format for [parseTagInfos]: each record opens with an RS
/// byte and splits on NUL, since a message can hold any other character.
/// `contents:subject` and `contents:body` leave a signed tag's signature
/// block out, where plain `contents` would show it.
const kTagInfoFormat =
    '%1e%(refname:strip=2)%00%(objecttype)%00%(taggername)'
    '%00%(taggeremail:trim)%00%(taggerdate:iso-strict)'
    '%00%(contents:subject)%00%(contents:body)';

/// Parses `for-each-ref --format=$kTagInfoFormat` output. A record that does
/// not have every field is skipped.
List<TagInfo> parseTagInfos(String out) {
  final tags = <TagInfo>[];
  for (final rec in out.split('\x1e')) {
    final f = rec.split('\x00');
    if (f.length != 7) continue;
    // A lightweight tag points straight at the commit, and git fills the
    // contents fields from the commit's message — not the tag's to show.
    if (f[1] != 'tag') {
      tags.add(TagInfo(name: f[0], annotated: false));
      continue;
    }
    tags.add(
      TagInfo(
        name: f[0],
        annotated: true,
        tagger: f[2],
        taggerEmail: f[3],
        date: DateTime.tryParse(f[4]),
        dateOffset: isoOffset(f[4]),
        subject: f[5],
        body: f[6].trimRight(),
      ),
    );
  }
  return tags;
}

/// How the repository signs: the key git would use, and whether a new tag
/// should be signed unless the user says otherwise.
class TagSigning {
  /// `user.signingkey`, null when unset (git then picks a default).
  final String? key;
  final bool byDefault;

  const TagSigning({this.key, this.byDefault = false});
}

/// The keys [parseTagSigning] reads, as a `config --get-regexp` pattern.
const kTagSigningKeys = r'^(user\.signingkey|tag\.gpgsign|commit\.gpgsign)$';

/// [TagSigning] from `config --get-regexp -z $kTagSigningKeys` output
/// (empty when none is set). Each record is `key\nvalue\0`, or `key\0` for a
/// bare key, which git reads as true; a key set twice takes its last value.
/// `tag.gpgSign` decides when it is set; otherwise the commit setting is what
/// the user signs with, and a tag follows it.
TagSigning parseTagSigning(String out) {
  final values = <String, String?>{};
  for (final rec in out.split('\x00')) {
    if (rec.isEmpty) continue;
    final nl = rec.indexOf('\n');
    if (nl < 0) {
      values[rec] = null;
    } else {
      values[rec.substring(0, nl)] = rec.substring(nl + 1);
    }
  }
  final key = values['user.signingkey']?.trim() ?? '';
  final tag = values.containsKey('tag.gpgsign')
      ? _gitBool(values['tag.gpgsign'])
      : null;
  return TagSigning(
    key: key.isEmpty ? null : key,
    byDefault:
        tag ??
        (values.containsKey('commit.gpgsign') &&
            _gitBool(values['commit.gpgsign'])),
  );
}

/// A config boolean as git reads it: a bare key, true/yes/on, or a non-zero
/// number is true. Anything git would reject counts as off.
bool _gitBool(String? v) {
  if (v == null) return true;
  final s = v.trim().toLowerCase();
  if (const {'true', 'yes', 'on'}.contains(s)) return true;
  final n = int.tryParse(s);
  return n != null && n != 0;
}
