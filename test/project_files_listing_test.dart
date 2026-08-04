// The project navigator reads one directory at a time, so a repo containing
// node_modules costs nothing until that folder is actually opened.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/project_files.dart';

void main() {
  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('mergelio_files_test');
  });

  tearDown(() {
    if (repo.existsSync()) repo.deleteSync(recursive: true);
  });

  Future<DirListing> list(String relDir) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(dirListingProvider(DirKey(repo.path, relDir)).future);
  }

  test('DirKey has value equality so the family caches per directory', () {
    expect(DirKey('/r', 'lib'), DirKey('/r', 'lib'));
    expect(DirKey('/r', 'lib').hashCode, DirKey('/r', 'lib').hashCode);
    expect(DirKey('/r', 'lib'), isNot(DirKey('/r', 'test')));
  });

  test(
    'directories sort before files, each case-insensitively by name',
    () async {
      File('${repo.path}/Zebra.txt').writeAsStringSync('z');
      File('${repo.path}/apple.txt').writeAsStringSync('a');
      Directory('${repo.path}/src').createSync();
      Directory('${repo.path}/Assets').createSync();

      final listing = await list('');
      expect(listing.entries.map((e) => e.name), [
        'Assets',
        'src',
        'apple.txt',
        'Zebra.txt',
      ]);
      expect(listing.entries.take(2).every((e) => e.isDir), isTrue);
    },
  );

  test('.git is hidden at the repository root', () async {
    Directory('${repo.path}/.git').createSync();
    File('${repo.path}/README.md').writeAsStringSync('r');

    final listing = await list('');
    expect(listing.entries.map((e) => e.name), ['README.md']);
  });

  test('a nested .git (submodule) is left visible', () async {
    Directory('${repo.path}/vendor/.git').createSync(recursive: true);

    final listing = await list('vendor');
    expect(listing.entries.map((e) => e.name), ['.git']);
  });

  test('a missing directory reports an error rather than throwing', () async {
    final listing = await list('does/not/exist');
    expect(listing.error, isNotNull);
    expect(listing.entries, isEmpty);
  });

  test('listing is capped and reports how many were dropped', () async {
    for (var i = 0; i < maxDirEntries + 25; i++) {
      File(
        '${repo.path}/f${i.toString().padLeft(5, '0')}.txt',
      ).writeAsStringSync('x');
    }

    final listing = await list('');
    expect(listing.entries.length, maxDirEntries);
    expect(listing.truncated, 25);
  });

  test('symlinks are reported without being followed', () async {
    Directory('${repo.path}/real').createSync();
    Link('${repo.path}/alias').createSync('${repo.path}/real');

    final listing = await list('');
    final alias = listing.entries.firstWhere((e) => e.name == 'alias');
    expect(alias.isLink, isTrue);
  });
}
