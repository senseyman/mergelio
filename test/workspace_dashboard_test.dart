import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/workspace.dart';

void main() {
  test('showDashboard keeps the active tab underneath', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.openRepo('/r/b');
    ctl.setActive(a.id);
    ctl.showDashboard();
    expect(ctl.state.dashboard, isTrue);
    expect(ctl.state.activeTabId, a.id);
  });

  test('activating a tab leaves the dashboard', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.showDashboard();
    ctl.setActive(a.id);
    expect(ctl.state.dashboard, isFalse);
  });

  test('opening a repository leaves the dashboard', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    ctl.showDashboard();
    ctl.openRepo('/r/b');
    expect(ctl.state.dashboard, isFalse);
    // Re-opening one already open is an activation and leaves it too.
    ctl.showDashboard();
    ctl.openRepo('/r/a');
    expect(ctl.state.dashboard, isFalse);
  });

  test('close others leaves the dashboard', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.openRepo('/r/b');
    ctl.showDashboard();
    ctl.closeOthers(a.id);
    expect(ctl.state.dashboard, isFalse);
  });

  test('closing the last tab drops the dashboard with it', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.showDashboard();
    ctl.closeTab(a.id);
    expect(ctl.state.dashboard, isFalse);
  });

  test('switching group keeps the dashboard up, re-scoped', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    final g = ctl.createGroup('Work');
    ctl.showDashboard();
    ctl.setActiveGroup(g.id);
    expect(ctl.state.dashboard, isTrue);
  });

  test('showDashboard does nothing with no repository open', () {
    final ctl = WorkspaceController();
    ctl.showDashboard();
    expect(ctl.state.dashboard, isFalse);
  });
}
