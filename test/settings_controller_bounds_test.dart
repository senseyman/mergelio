import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

/// The bounds the settings controller holds sizes to, the defaults its
/// per-id toggles start from, and that every change is persisted.
void main() {
  late _RecordingRepo repo;
  late SettingsController c;

  setUp(() {
    repo = _RecordingRepo();
    c = SettingsController(repo, const AppSettings());
  });

  group('sizes are held within their bounds', () {
    void bounds(
      String name,
      void Function(SettingsController, double) set,
      double Function(AppSettings) get, {
      required double min,
      required double max,
    }) {
      test(name, () {
        set(c, -1000);
        expect(get(c.state), min);
        set(c, 100000);
        expect(get(c.state), max);
        final mid = (min + max) / 2;
        set(c, mid);
        expect(get(c.state), mid);
      });
    }

    bounds(
      'left panel',
      (ctl, v) => ctl.setLeftWidth(v),
      (s) => s.leftWidth,
      min: 200,
      max: 460,
    );
    bounds(
      'right panel',
      (ctl, v) => ctl.setRightWidth(v),
      (s) => s.rightWidth,
      min: 300,
      max: 560,
    );
    bounds(
      'files navigator',
      (ctl, v) => ctl.setFilesNavWidth(v),
      (s) => s.filesNavWidth,
      min: 200,
      max: 560,
    );
    bounds(
      'graph branch column',
      (ctl, v) => ctl.setGraphBranchWidth(v),
      (s) => s.graphBranchWidth,
      min: 40,
      max: 400,
    );
    bounds(
      'terminal height',
      (ctl, v) => ctl.setTerminalHeight(v),
      (s) => s.terminalHeight,
      min: 140,
      max: 520,
    );
    bounds(
      'diff sheet height',
      (ctl, v) => ctl.setDiffHeight(v),
      (s) => s.diffHeight,
      min: 0.28,
      max: 0.86,
    );
  });

  group('graph rail width', () {
    test('zero or less means auto-size', () {
      c.setGraphRailWidth(-5);
      expect(c.state.graphRailWidth, 0);
      c.setGraphRailWidth(0);
      expect(c.state.graphRailWidth, 0);
    });

    test('a dragged width is floored so the rail never vanishes', () {
      c.setGraphRailWidth(3);
      expect(c.state.graphRailWidth, 24);
    });

    test('and capped', () {
      c.setGraphRailWidth(5000);
      expect(c.state.graphRailWidth, 1200);
    });
  });

  group('toggles', () {
    test('theme flips between dark and light', () {
      c.setThemeMode(ThemeMode.dark);
      c.toggleTheme();
      expect(c.state.themeMode, ThemeMode.light);
      c.toggleTheme();
      expect(c.state.themeMode, ThemeMode.dark);
    });

    test('the system theme toggles to dark', () {
      c.setThemeMode(ThemeMode.system);
      c.toggleTheme();
      expect(c.state.themeMode, ThemeMode.dark);
    });

    test('a section starts expanded and collapses on first toggle', () {
      c.toggleSection('stashes');
      expect(c.state.collapsedSections['stashes'], isTrue);
      c.toggleSection('stashes');
      expect(c.state.collapsedSections['stashes'], isFalse);
    });

    test('a graph column starts shown and hides on first toggle', () {
      c.toggleGraphCol('author');
      expect(c.state.graphCols['author'], isFalse);
      c.toggleGraphCol('author');
      expect(c.state.graphCols['author'], isTrue);
    });

    test('terminal opens and closes', () {
      final start = c.state.terminalOpen;
      c.toggleTerminal();
      expect(c.state.terminalOpen, !start);
      c.setTerminalOpen(false);
      expect(c.state.terminalOpen, isFalse);
    });

    test(
      'left panel, compact graph, hidden ignored files, files navigator',
      () {
        final s = c.state;
        c
          ..toggleLeftCollapsed()
          ..toggleGraphCompact()
          ..toggleFilesHideIgnored()
          ..toggleFilesNavCollapsed()
          ..toggleFilesAsTree();
        expect(c.state.leftCollapsed, !s.leftCollapsed);
        expect(c.state.graphCompact, !s.graphCompact);
        expect(c.state.filesHideIgnored, !s.filesHideIgnored);
        expect(c.state.filesNavCollapsed, !s.filesNavCollapsed);
        expect(c.state.filesAsTree, !s.filesAsTree);
      },
    );
  });

  group('values', () {
    test('the editor command is stored trimmed', () {
      c.setEditorCommand('  code -w  ');
      expect(c.state.editorCommand, 'code -w');
    });

    test('the last update check is stored as epoch milliseconds', () {
      final when = DateTime.utc(2026, 11, 10, 12);
      c.setUpdateLastCheck(when);
      expect(c.state.updateLastCheckMs, when.millisecondsSinceEpoch);
    });

    test('diff whitespace and context are set together', () {
      c.setDiffViewOptions('all', 7);
      expect(c.state.diffWhitespace, 'all');
      expect(c.state.diffContextLines, 7);
    });

    test('plain setters', () {
      c
        ..setConfirmDestructive(false)
        ..setRestoreTabs(false)
        ..setPullStrategy('rebase')
        ..setPullAutostash(true)
        ..setDateFormat('iso')
        ..setClockFormat('24h')
        ..setLocaleCode('uk')
        ..setTelemetryEnabled(true)
        ..setUpdateConsent('yes')
        ..setUpdateSkippedVersion('9.9.9')
        ..setGroupStyle('rail')
        ..setDiffSplit(true);
      final s = c.state;
      expect(s.confirmDestructive, isFalse);
      expect(s.restoreTabs, isFalse);
      expect(s.pullStrategy, 'rebase');
      expect(s.pullAutostash, isTrue);
      expect(s.dateFormat, 'iso');
      expect(s.clockFormat, '24h');
      expect(s.localeCode, 'uk');
      expect(s.telemetryEnabled, isTrue);
      expect(s.updateConsent, 'yes');
      expect(s.updateSkippedVersion, '9.9.9');
      expect(s.groupStyle, 'rail');
      expect(s.diffSplit, isTrue);
    });
  });

  group('saved themes', () {
    test('deleting an unknown theme changes and saves nothing', () {
      c.deleteSavedTheme('nope');
      expect(repo.saved, isEmpty);
    });

    test('applying an unknown theme changes nothing', () {
      final before = c.state;
      c.applySavedTheme('nope');
      expect(c.state, before);
      expect(repo.saved, isEmpty);
    });
  });

  group('persistence', () {
    test('every change is saved', () {
      c.setLeftWidth(300);
      c.toggleSection('x');
      expect(repo.saved, hasLength(2));
      expect(repo.saved.last, c.state);
    });

    test('a failed save keeps the change in memory', () async {
      final failing = SettingsController(
        _RecordingRepo(fail: true),
        const AppSettings(),
      );
      failing.setLeftWidth(300);
      await Future<void>.delayed(Duration.zero);
      expect(failing.state.leftWidth, 300);
    });
  });
}

class _RecordingRepo implements SettingsRepository {
  final bool fail;
  _RecordingRepo({this.fail = false});

  final saved = <AppSettings>[];

  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) {
    if (fail) return Future.error(StateError('read-only disk'));
    saved.add(settings);
    return Future.value();
  }
}
