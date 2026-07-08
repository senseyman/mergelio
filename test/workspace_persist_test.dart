import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  test('open tabs persist and restore in order', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);

    c.openRepo('/repos/alpha');
    c.openRepo('/repos/beta');
    c.openRepo('/repos/gamma');

    expect(await WorkspaceController.restorePaths(store), [
      '/repos/alpha',
      '/repos/beta',
      '/repos/gamma',
    ]);
  });

  test('closing a tab updates the persisted set', () async {
    final store = InMemoryKeyValueStore();
    final c = WorkspaceController(store);
    final a = c.openRepo('/a');
    c.openRepo('/b');
    c.closeTab(a.id);

    expect(await WorkspaceController.restorePaths(store), ['/b']);
  });

  test('restorePaths is empty when nothing was saved', () async {
    expect(
      await WorkspaceController.restorePaths(InMemoryKeyValueStore()),
      isEmpty,
    );
  });
}
