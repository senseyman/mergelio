import 'package:pub_semver/pub_semver.dart';

/// Directory the bundled notes live in, as asset keys spell it.
const releaseNotesDir = 'release_notes/';

final _notesName = RegExp(r'^release_notes/(\d+\.\d+\.\d+)\.([a-z]{2})\.md$');

/// Versions that have bundled notes, each with the languages it has them in.
/// A version counts only when its English file exists: English is what every
/// other language falls back to.
Map<Version, Set<String>> parseNotesAssets(Iterable<String> assetKeys) {
  final found = <Version, Set<String>>{};
  for (final key in assetKeys) {
    final m = _notesName.firstMatch(key);
    if (m == null) continue;
    found.putIfAbsent(Version.parse(m[1]!), () => {}).add(m[2]!);
  }
  found.removeWhere((_, langs) => !langs.contains('en'));
  return found;
}

/// Notes to show after an upgrade: every version newer than [lastSeen] up to
/// and including [current], newest first. Nothing on a fresh install (no
/// [lastSeen]) or when the app did not move forward.
List<Version> versionsToShow({
  required Version? lastSeen,
  required Version current,
  required Iterable<Version> available,
}) {
  if (lastSeen == null || current <= lastSeen) return const [];
  return available.where((v) => v > lastSeen && v <= current).toList()
    ..sort((a, b) => b.compareTo(a));
}

/// Asset key for [version]'s notes in [lang], falling back to English.
String notesAssetFor(Version version, String lang, Set<String> langs) =>
    '$releaseNotesDir$version.${langs.contains(lang) ? lang : 'en'}.md';
