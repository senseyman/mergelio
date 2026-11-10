import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/state/recents.dart';

/// Ordering, pinning and the size cap of the Welcome screen's recents list,
/// and that every change is persisted.
void main() {
  late AppDatabase db;
  late RecentsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = RecentsRepository(db);
  });
  tearDown(() => db.close());

  RecentsController ctl([List<RecentRepo> initial = const []]) =>
      RecentsController(repo, initial);

  List<String> paths(RecentsController c) => [for (final r in c.state) r.path];

  /// The save is fire-and-forget; let it land before reading the database.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a new repository goes to the top', () {
    final c = ctl(const [RecentRepo(name: 'a', path: '/a')]);
    c.add('b', '/b');
    expect(paths(c), ['/b', '/a']);
  });

  test('re-adding a repository moves it to the top without duplicating', () {
    final c = ctl(const [
      RecentRepo(name: 'a', path: '/a'),
      RecentRepo(name: 'b', path: '/b'),
    ]);
    c.add('b', '/b');
    expect(paths(c), ['/b', '/a']);
  });

  test('re-adding refreshes the name and keeps the pin', () {
    final c = ctl(const [
      RecentRepo(name: 'old', path: '/a', pinned: true),
      RecentRepo(name: 'b', path: '/b'),
    ]);
    c.add('new', '/a');
    expect(
      c.state.first,
      const RecentRepo(name: 'new', path: '/a', pinned: true),
    );
  });

  test('keeps at most twelve entries, dropping the oldest', () {
    final c = ctl();
    for (var i = 0; i < 14; i++) {
      c.add('r$i', '/r$i');
    }
    expect(c.state, hasLength(12));
    expect(c.state.first.path, '/r13');
    expect(paths(c), isNot(contains('/r0')));
    expect(paths(c), isNot(contains('/r1')));
  });

  test('pinned entries sort ahead of unpinned ones, keeping their order', () {
    final c = ctl(const [
      RecentRepo(name: 'a', path: '/a'),
      RecentRepo(name: 'b', path: '/b'),
      RecentRepo(name: 'c', path: '/c'),
    ]);
    c.togglePin('/c');
    expect(paths(c), ['/c', '/a', '/b']);
    // Pinning /b keeps it behind /c, which was already ahead of it.
    c.togglePin('/b');
    expect(paths(c), ['/c', '/b', '/a']);
    expect([for (final r in c.state) r.pinned], [true, true, false]);
  });

  test('a new entry lands below the pinned ones', () {
    final c = ctl(const [RecentRepo(name: 'p', path: '/p', pinned: true)]);
    c.add('n', '/n');
    expect(paths(c), ['/p', '/n']);
  });

  test('toggling a pin twice unpins', () {
    final c = ctl(const [
      RecentRepo(name: 'a', path: '/a'),
      RecentRepo(name: 'b', path: '/b'),
    ]);
    c.togglePin('/b');
    c.togglePin('/b');
    expect(c.state.every((r) => !r.pinned), isTrue);
  });

  test('toggling an unknown path changes nothing', () {
    final c = ctl(const [RecentRepo(name: 'a', path: '/a')]);
    c.togglePin('/nope');
    expect(c.state, const [RecentRepo(name: 'a', path: '/a')]);
  });

  test('remove drops only that path', () {
    final c = ctl(const [
      RecentRepo(name: 'a', path: '/a'),
      RecentRepo(name: 'b', path: '/b'),
    ]);
    c.remove('/a');
    expect(paths(c), ['/b']);
  });

  test('every change is saved', () async {
    final c = ctl();
    c.add('a', '/a');
    c.add('b', '/b');
    c.togglePin('/a');
    await settle();
    expect(await repo.load(), c.state);

    c.remove('/a');
    await settle();
    expect(await repo.load(), const [RecentRepo(name: 'b', path: '/b')]);
  });

  test('a failed save keeps the in-memory list', () async {
    final c = RecentsController(_FailingRepo(db), const []);
    c.add('a', '/a');
    await settle();
    expect(paths(c), ['/a']);
  });

  test('the provider must be overridden before use', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(recentsProvider), throwsA(anything));
  });
}

class _FailingRepo extends RecentsRepository {
  _FailingRepo(super.db);

  @override
  Future<void> save(List<RecentRepo> items) =>
      Future.error(StateError('disk full'));
}
