import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  group('Profile.label', () {
    test('round-trips through JSON', () {
      const p = Profile(
        id: 'p1',
        label: 'Work',
        name: 'Dev Name',
        email: 'dev@work.com',
        colorValue: 0xFF112233,
      );
      final back = Profile.fromJson(p.toJson());
      expect(back.label, 'Work');
      expect(back.name, 'Dev Name');
      expect(back.email, 'dev@work.com');
    });

    test('label falls back to name for legacy JSON without a label', () {
      final back = Profile.fromJson({
        'id': 'p1',
        'name': 'Legacy',
        'email': 'l@e.com',
        'color': 0xFF000000,
      });
      expect(back.label, 'Legacy');
    });
  });

  group('profile-scoped workspace', () {
    test('saves target the per-profile key, not the global one', () async {
      final store = InMemoryKeyValueStore();
      final c = WorkspaceController(store, 'pX');
      c.openRepo('/r/a');
      expect(await store.get('openTabs:pX'), isNotNull);
      expect(await store.get('openTabs'), isNull);
    });

    test('two profiles keep separate workspaces across switches', () async {
      final store = InMemoryKeyValueStore();
      final c = WorkspaceController(store, 'p1');
      c.openRepo('/work/alpha');

      // Switch to an empty p2 and open a different repo.
      c.useProfile(
        'p2',
        await WorkspaceController.restoreSessionFor(store, 'p2'),
      );
      expect(c.state.tabs, isEmpty);
      c.openRepo('/personal/beta');

      // Back to p1 → its workspace is restored, p2's is untouched on disk.
      c.useProfile(
        'p1',
        await WorkspaceController.restoreSessionFor(store, 'p1'),
      );
      expect(c.state.tabs.map((t) => t.path), ['/work/alpha']);

      final p2 = await WorkspaceController.restoreSessionFor(store, 'p2');
      expect(p2.tabs.map((t) => t.path), ['/personal/beta']);
    });
  });
}
