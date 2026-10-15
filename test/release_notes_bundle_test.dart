import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/release_notes/release_notes.dart';

// Guards the hand-written files: a misnamed one is silently never shown.
void main() {
  test('every notes file is named so the app picks it up', () {
    final files = Directory('release_notes')
        .listSync()
        .whereType<File>()
        .map((f) => '$releaseNotesDir${f.uri.pathSegments.last}')
        .toSet();
    expect(files, isNotEmpty);

    final picked = {
      for (final e in parseNotesAssets(files).entries)
        for (final lang in e.value) '$releaseNotesDir${e.key}.$lang.md',
    };
    expect(
      files.difference(picked),
      isEmpty,
      reason: 'misnamed, or a language without its English file',
    );
  });

  test('pubspec bundles the notes directory', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('\n  assets:\n    - release_notes/\n'),
    );
  });
}
