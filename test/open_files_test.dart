// Which files Files mode has open, which one is on top, and what happens to
// that set as files are closed, renamed or deleted underneath it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/open_files.dart';

void main() {
  late ProviderContainer c;

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  OpenFiles state() => c.read(openFilesProvider('/r'));
  OpenFilesNotifier notifier() => c.read(openFilesProvider('/r').notifier);

  test('nothing is open to begin with', () {
    expect(state().paths, isEmpty);
    expect(state().active, isNull);
  });

  test('opening a file adds it and makes it active', () {
    notifier().open('a.txt');

    expect(state().paths, ['a.txt']);
    expect(state().active, 'a.txt');
  });

  test('opening an already open file focuses it instead of duplicating', () {
    notifier()
      ..open('a.txt')
      ..open('b.txt')
      ..open('a.txt');

    expect(state().paths, ['a.txt', 'b.txt']);
    expect(state().active, 'a.txt');
  });

  test('closing the active tab activates its neighbour', () {
    notifier()
      ..open('a.txt')
      ..open('b.txt')
      ..open('c.txt')
      ..activate('b.txt')
      ..close('b.txt');

    expect(state().paths, ['a.txt', 'c.txt']);
    expect(state().active, 'c.txt');
  });

  test('closing the last remaining tab leaves nothing active', () {
    notifier()
      ..open('a.txt')
      ..close('a.txt');

    expect(state().paths, isEmpty);
    expect(state().active, isNull);
  });

  test('closing an inactive tab leaves the active one alone', () {
    notifier()
      ..open('a.txt')
      ..open('b.txt')
      ..close('a.txt');

    expect(state().active, 'b.txt');
  });

  test('closing drops the tab dirty and gone marks with it', () {
    notifier()
      ..open('a.txt')
      ..setDirty('a.txt', true)
      ..markGone('a.txt')
      ..close('a.txt');

    expect(state().dirty, isEmpty);
    expect(state().gone, isEmpty);
  });

  test('a dirty tab is reported until it is saved', () {
    notifier()
      ..open('a.txt')
      ..setDirty('a.txt', true);
    expect(state().dirty, {'a.txt'});

    notifier().setDirty('a.txt', false);
    expect(state().dirty, isEmpty);
  });

  test('unsaved marks are dropped when the editors go away', () {
    notifier()
      ..open('a.txt')
      ..setDirty('a.txt', true)
      ..clearDirty();

    expect(state().dirty, isEmpty);
    expect(state().paths, ['a.txt']);
  });

  test('a renamed file keeps its tab, its place and its marks', () {
    notifier()
      ..open('a.txt')
      ..open('b.txt')
      ..activate('a.txt')
      ..setDirty('a.txt', true)
      ..rename('a.txt', 'sub/renamed.txt');

    expect(state().paths, ['sub/renamed.txt', 'b.txt']);
    expect(state().active, 'sub/renamed.txt');
    expect(state().dirty, {'sub/renamed.txt'});
  });

  test('renaming a file nothing has open changes nothing', () {
    notifier()
      ..open('a.txt')
      ..rename('other.txt', 'moved.txt');

    expect(state().paths, ['a.txt']);
  });

  test('a renamed-onto path does not end up open twice', () {
    notifier()
      ..open('a.txt')
      ..open('b.txt')
      ..rename('a.txt', 'b.txt');

    expect(state().paths, ['b.txt']);
    expect(state().active, 'b.txt');
  });

  test('a deleted file keeps its tab but marks it gone', () {
    // The text stays visible; what stops is saving it back, which would
    // recreate a file the user deleted.
    notifier()
      ..open('a.txt')
      ..markGone('a.txt');

    expect(state().paths, ['a.txt']);
    expect(state().gone, {'a.txt'});
  });

  test('a file that comes back is no longer gone', () {
    notifier()
      ..open('a.txt')
      ..markGone('a.txt')
      ..markPresent('a.txt');

    expect(state().gone, isEmpty);
  });

  test('a file nothing has open is never marked gone', () {
    notifier().markGone('a.txt');

    expect(state().gone, isEmpty);
  });

  test('restoring reopens a persisted set without touching disk', () {
    notifier().restore(const ['a.txt', 'b.txt'], active: 'b.txt');

    expect(state().paths, ['a.txt', 'b.txt']);
    expect(state().active, 'b.txt');
    expect(state().dirty, isEmpty);
  });

  test('restoring an active path outside the set falls back to the first', () {
    notifier().restore(const ['a.txt'], active: 'gone.txt');

    expect(state().active, 'a.txt');
  });

  test('each repository carries its own tabs', () {
    notifier().open('a.txt');
    c.read(openFilesProvider('/other').notifier).open('z.txt');

    expect(state().paths, ['a.txt']);
    expect(c.read(openFilesProvider('/other')).paths, ['z.txt']);
  });
}
