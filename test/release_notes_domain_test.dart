import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/release_notes/release_notes.dart';
import 'package:pub_semver/pub_semver.dart';

Version v(String s) => Version.parse(s);

void main() {
  group('parseNotesAssets', () {
    test('collects versions and their languages', () {
      final got = parseNotesAssets([
        'release_notes/1.9.0.en.md',
        'release_notes/1.9.0.uk.md',
        'release_notes/1.10.0.en.md',
      ]);
      expect(got, {
        v('1.9.0'): {'en', 'uk'},
        v('1.10.0'): {'en'},
      });
    });

    test('ignores other assets and malformed names', () {
      expect(
        parseNotesAssets([
          'fonts/Inter.ttf',
          'release_notes/1.9.en.md',
          'release_notes/1.9.0.EN.md',
          'release_notes/1.9.0.en.txt',
          'release_notes/1.9.0-beta.en.md',
          'release_notes/1.9.0+25.en.md',
          'other/release_notes/1.9.0.en.md',
        ]),
        isEmpty,
      );
    });

    test('drops a version with no English file', () {
      expect(parseNotesAssets(['release_notes/1.9.0.uk.md']), isEmpty);
    });
  });

  group('versionsToShow', () {
    final available = [v('1.8.0'), v('1.9.0'), v('1.10.0'), v('2.0.0')];
    List<Version> run(String? lastSeen, String current) => versionsToShow(
      lastSeen: lastSeen == null ? null : v(lastSeen),
      current: v(current),
      available: available,
    );

    test('fresh install shows nothing', () {
      expect(run(null, '1.10.0'), isEmpty);
    });
    test('same version shows nothing', () {
      expect(run('1.9.0', '1.9.0'), isEmpty);
    });
    test('downgrade shows nothing', () {
      expect(run('1.10.0', '1.9.0'), isEmpty);
    });
    test('single upgrade shows the current version', () {
      expect(run('1.8.0', '1.9.0'), [v('1.9.0')]);
    });
    test('skipped versions show newest first, compared numerically', () {
      expect(run('1.8.0', '1.10.0'), [v('1.10.0'), v('1.9.0')]);
    });
    test('versions above current are left out', () {
      expect(run('1.9.0', '1.10.0'), [v('1.10.0')]);
    });
    test('upgrade to a version without notes shows nothing', () {
      expect(run('1.10.0', '1.10.1'), isEmpty);
    });
    test('a skipped version with notes shows even if current has none', () {
      expect(run('1.8.5', '1.9.3'), [v('1.9.0')]);
    });
  });

  group('notesAssetFor', () {
    test('uses the requested language when present', () {
      expect(
        notesAssetFor(v('1.9.0'), 'uk', {'en', 'uk'}),
        'release_notes/1.9.0.uk.md',
      );
    });
    test('falls back to English', () {
      expect(
        notesAssetFor(v('1.9.0'), 'uk', {'en'}),
        'release_notes/1.9.0.en.md',
      );
      expect(
        notesAssetFor(v('1.9.0'), 'de', {'en', 'uk'}),
        'release_notes/1.9.0.en.md',
      );
    });
  });
}
