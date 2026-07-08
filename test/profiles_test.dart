import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/profiles.dart';

Profile _p(String id, String name) =>
    Profile(id: id, name: name, email: '$name@e.com', colorValue: 0xFF112233);

void main() {
  group('ProfilesController', () {
    late InMemoryKeyValueStore store;
    late ProfilesController c;

    setUp(() {
      store = InMemoryKeyValueStore();
      c = ProfilesController(store, const ProfilesState());
    });

    test('the first profile added becomes active', () {
      c.add(_p('1', 'Maria'));
      expect(c.state.active?.name, 'Maria');
    });

    test('update edits in place; remove reassigns active', () {
      c.add(_p('1', 'Maria'));
      c.add(_p('2', 'Ivan'));
      c.update(_p('1', 'Maria').copyWith(email: 'new@e.com'));
      expect(
        c.state.profiles.firstWhere((p) => p.id == '1').email,
        'new@e.com',
      );

      c.setActive('2');
      c.remove('2');
      expect(c.state.active?.id, '1'); // fell back to the remaining profile
    });

    test('changes persist and reload', () async {
      c.add(_p('1', 'Maria'));
      c.add(_p('2', 'Ivan'));
      c.setActive('2');

      final reloaded = await ProfilesController.load(store);
      expect(reloaded.profiles.map((p) => p.name), ['Maria', 'Ivan']);
      expect(reloaded.active?.id, '2');
    });

    test('load returns empty state when nothing was saved', () async {
      expect((await ProfilesController.load(store)).profiles, isEmpty);
    });
  });
}
