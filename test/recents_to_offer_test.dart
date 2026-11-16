import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/recents.dart';

const _a = RecentRepo(name: 'a', path: '/r/a');
const _b = RecentRepo(name: 'b', path: '/r/b');
const _c = RecentRepo(name: 'c', path: '/r/c');

List<String> _paths(List<RecentRepo> rs) => [for (final r in rs) r.path];

void main() {
  test('keeps the stored order', () {
    expect(_paths(recentsToOffer([_a, _b, _c], const [])), [
      '/r/a',
      '/r/b',
      '/r/c',
    ]);
  });

  test('drops repositories already open in a tab', () {
    expect(_paths(recentsToOffer([_a, _b, _c], const ['/r/b'])), [
      '/r/a',
      '/r/c',
    ]);
  });

  test('the same folder spelled differently counts as open', () {
    expect(_paths(recentsToOffer([_a, _b, _c], const ['/r/b/'])), [
      '/r/a',
      '/r/c',
    ]);
  });

  test('nothing recent offers nothing', () {
    expect(recentsToOffer(const [], const ['/r/a']), isEmpty);
  });

  test('normalises each path once, not once per pair', () {
    // Normalising resolves symlinks on disk, and this runs while the tab bar
    // builds; a pairwise compare would do recents × tabs filesystem calls.
    var calls = 0;
    String key(String path) {
      calls++;
      return path;
    }

    recentsToOffer([_a, _b, _c], const ['/x', '/y', '/z', '/w'], key: key);

    expect(calls, 3 + 4);
  });
}
