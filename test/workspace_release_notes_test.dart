import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:pub_semver/pub_semver.dart';

final v19 = Version.parse('1.9.0');
final v110 = Version.parse('1.10.0');

void main() {
  test('opening selects the notes tab over the active repo', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v19]);
    expect(ctl.state.releaseNotes, [v19]);
    expect(ctl.state.showReleaseNotes, isTrue);
    expect(ctl.state.activeTabId, a.id);
    expect(ctl.state.shownTab, isNull);
  });

  test('opens with no repository tabs at all', () {
    final ctl = WorkspaceController();
    ctl.openReleaseNotes([v19]);
    expect(ctl.state.showReleaseNotes, isTrue);
    expect(ctl.state.tabs, isEmpty);
  });

  test('clicking the already-active repo tab returns to it', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v19]);
    ctl.setActive(a.id);
    expect(ctl.state.showReleaseNotes, isFalse);
    expect(ctl.state.releaseNotes, [v19]);
    expect(ctl.state.shownTab?.id, a.id);
  });

  test('opening or re-opening a repository leaves the notes', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v19]);
    ctl.openRepo('/r/b');
    expect(ctl.state.showReleaseNotes, isFalse);
    ctl.selectReleaseNotes();
    ctl.openRepo('/r/a');
    expect(ctl.state.showReleaseNotes, isFalse);
  });

  test('dashboard and notes replace each other', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v19]);
    ctl.showDashboard();
    expect(ctl.state.dashboard, isTrue);
    expect(ctl.state.showReleaseNotes, isFalse);
    ctl.selectReleaseNotes();
    expect(ctl.state.dashboard, isFalse);
    expect(ctl.state.showReleaseNotes, isTrue);
  });

  test('close others leaves the notes', () {
    final ctl = WorkspaceController();
    final a = ctl.openRepo('/r/a');
    ctl.openRepo('/r/b');
    ctl.openReleaseNotes([v19]);
    ctl.closeOthers(a.id);
    expect(ctl.state.showReleaseNotes, isFalse);
    expect(ctl.state.releaseNotes, [v19]);
  });

  test('closing clears the tab', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    ctl.openReleaseNotes([v19]);
    ctl.closeReleaseNotes();
    expect(ctl.state.releaseNotes, isNull);
    expect(ctl.state.showReleaseNotes, isFalse);
    expect(ctl.state.shownTab, isNotNull);
  });

  test('select does nothing when the tab is closed', () {
    final ctl = WorkspaceController();
    ctl.openRepo('/r/a');
    ctl.selectReleaseNotes();
    expect(ctl.state.showReleaseNotes, isFalse);
  });

  test('re-opening an open tab keeps its versions', () {
    final ctl = WorkspaceController();
    ctl.openReleaseNotes([v110, v19]);
    ctl.openReleaseNotes([v110]);
    expect(ctl.state.releaseNotes, [v110, v19]);
    expect(ctl.state.showReleaseNotes, isTrue);
  });

  test('switching profile keeps the notes tab', () {
    final ctl = WorkspaceController();
    ctl.openReleaseNotes([v19]);
    ctl.useProfile('p1', const WorkspaceSession());
    expect(ctl.state.releaseNotes, [v19]);
    expect(ctl.state.showReleaseNotes, isTrue);
  });
}
