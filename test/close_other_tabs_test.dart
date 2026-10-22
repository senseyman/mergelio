// "Close others" takes several repositories at once, and anything unsaved in
// them with it, so each one is asked first — the same as closing one tab.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/unsaved_guard.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/app_tab_bar.dart';

void main() {
  late UnsavedGuards guards;
  late WorkspaceController ctl;
  late RepoTab keep;

  setUp(() {
    guards = UnsavedGuards();
    ctl = WorkspaceController()
      ..openRepo('/a')
      ..openRepo('/b')
      ..openRepo('/c');
    keep = ctl.state.tabs.first;
  });

  List<String> openPaths() => [for (final t in ctl.state.tabs) t.path];

  test('with nothing unsaved the others close', () async {
    await closeOtherTabs(guards, ctl, ctl.state.tabs, keep);
    expect(openPaths(), ['/a']);
  });

  test('every other repository is asked', () async {
    final asked = <String>[];
    for (final path in ['/a', '/b', '/c']) {
      guards.register(path, () async {
        asked.add(path);
        return true;
      });
    }

    await closeOtherTabs(guards, ctl, ctl.state.tabs, keep);

    expect(asked, ['/b', '/c']);
    expect(openPaths(), ['/a']);
  });

  test('one refusal keeps every tab open', () async {
    guards
      ..register('/b', () async => true)
      ..register('/c', () async => false);

    await closeOtherTabs(guards, ctl, ctl.state.tabs, keep);

    expect(openPaths(), ['/a', '/b', '/c']);
  });
}
