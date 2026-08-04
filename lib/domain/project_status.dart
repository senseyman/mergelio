import 'git/models.dart';

/// What the navigator says about one entry on disk. [unknown] is what a failed
/// `git ls-files` degrades to: browsing and editing carry on, only the badge
/// and the dimming go away.
enum EntryStatus { clean, modified, untracked, ignored, unknown }

/// Indexes the working-file list by path so a classification pass costs one
/// lookup per row rather than a scan. A rename is reachable under both its old
/// and new path, since a row may be showing either.
Map<String, WorkingFile> indexWorking(List<WorkingFile> files) {
  final index = <String, WorkingFile>{};
  for (final f in files) {
    index[f.path] = f;
    final orig = f.origPath;
    if (orig != null) index[orig] = f;
  }
  return index;
}

/// What git says about [relPath]. Pure: [tracked] comes from `git ls-files`
/// (null when that read failed), [ignored] from `git check-ignore`, [working]
/// from the porcelain status the repository already holds.
EntryStatus classifyEntry({
  required String relPath,
  required bool? tracked,
  required bool ignored,
  required Map<String, WorkingFile> working,
}) {
  if (tracked == null) return EntryStatus.unknown;
  final change = working[relPath];
  // A tracked file that was edited is reported as edited whatever the ignore
  // rules say — git honours the index over .gitignore, and so does the badge.
  if (change != null && !change.isUntracked) {
    return change.isStaged || change.isUnstaged
        ? EntryStatus.modified
        : EntryStatus.clean;
  }
  if (ignored) return EntryStatus.ignored;
  return tracked ? EntryStatus.clean : EntryStatus.untracked;
}
