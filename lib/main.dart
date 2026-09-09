import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/logging.dart';
import 'data/app_database.dart';
import 'data/kv_store.dart';
import 'data/settings_repository.dart';
import 'domain/git/askpass.dart';
import 'domain/window_placement.dart';
import 'state/diagnostics.dart';
import 'state/operation_journal.dart';
import 'state/profiles.dart';
import 'state/recents.dart';
import 'state/settings.dart';
import 'state/settings_controller.dart';
import 'state/window_persist.dart';
import 'state/workspace.dart';
import 'ui/askpass/askpass_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // git and ssh re-launch the app with this flag when they need a passphrase or
  // password; that launch is one small dialog, not the workspace.
  final prompt = askpassPrompt(args);
  if (prompt != null) {
    return runAskpassApp(prompt, marked: askpassWantsMarker(args));
  }

  // Start the log file first, so everything below — including a startup crash —
  // leaves a trace the user can hand over in a bug report.
  await initFileLogging();
  appLog.info('launching', scope: 'startup');

  // Put the credential-prompt helper in place before anything can talk to a
  // remote, so the first fetch of the session can already ask.
  await initAskpass();

  // Error boundary: log framework and async errors instead of taking the whole
  // app down, and show a contained fallback in place of a failed subtree.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLog.error(
      'uncaught framework error',
      details.exception,
      details.stack,
      'flutter',
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    appLog.error('uncaught async error', error, stack, 'flutter');
    return true;
  };
  ErrorWidget.builder = (details) => const _FallbackErrorWidget();

  await windowManager.ensureInitialized();

  // Load persisted state defensively — a broken database must never block
  // startup or leave the user without a window.
  final db = AppDatabase();
  final settingsRepo = DriftSettingsRepository(db);
  final recentsRepo = RecentsRepository(db);
  final kv = DriftKeyValueStore(db);
  var settings = const AppSettings();
  var recents = const <RecentRepo>[];
  var profiles = const ProfilesState();
  var session = const WorkspaceSession();
  var interruptedOps = const <String>[];
  try {
    settings = await settingsRepo.load();
    recents = await recentsRepo.load();
    profiles = await ProfilesController.load(kv);
    // Workspaces are per-profile: restore the active profile's session (an
    // empty one until the first profile is created).
    final activeProfile = profiles.activeId;
    session = activeProfile != null
        ? await WorkspaceController.restoreSessionFor(kv, activeProfile)
        : const WorkspaceSession();
    // Scan each restored repo's journal: an op still pending means the app
    // stopped mid-operation last time, so warn the user on launch.
    final notices = <String>[];
    for (final tab in session.tabs) {
      final j = OperationJournal(kv, tab.path);
      await j.load();
      for (final r in j.interrupted) {
        notices.add('${tab.path.split('/').last}: ${r.label}');
      }
    }
    interruptedOps = notices;
  } catch (e, st) {
    appLog.error('state load failed, using defaults', e, st, 'startup');
  }

  // Restore the window where the user left it, but only if that place still
  // exists — monitors get unplugged and resolutions change between runs.
  const minimumSize = Size(960, 600);
  final displays = await _connectedDisplays();
  final trustPosition = positionIsTrustworthy(
    displays,
    isWindows: Platform.isWindows,
  );
  final placement = resolveWindowPlacement(
    x: trustPosition ? settings.windowX : null,
    y: trustPosition ? settings.windowY : null,
    savedSize: Size(settings.windowWidth, settings.windowHeight),
    minimumSize: minimumSize,
    displays: displayBounds(displays),
  );
  final options = WindowOptions(
    size: placement.size,
    minimumSize: minimumSize,
    center: placement.position == null,
    title: 'Mergelio',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options);
  final position = placement.position;
  if (position != null) await windowManager.setPosition(position);

  final settingsController = SettingsController(settingsRepo, settings);
  windowManager.addListener(
    WindowGeometryPersist(
      readBounds: windowManager.getBounds,
      readMaximized: windowManager.isMaximized,
      readFullScreen: windowManager.isFullScreen,
      write: (b) =>
          settingsController.setWindowBounds(b.left, b.top, b.width, b.height),
    ),
  );

  runApp(
    ProviderScope(
      // Provider failures surface in the UI as "could not read …" and are
      // otherwise invisible; the observer puts them in the log.
      observers: const [LoggingProviderObserver()],
      overrides: [
        settingsProvider.overrideWith((ref) => settingsController),
        recentsProvider.overrideWith(
          (ref) => RecentsController(recentsRepo, recents),
        ),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(kv, profiles),
        ),
        workspaceProvider.overrideWith((ref) {
          final c = WorkspaceController(kv, profiles.activeId);
          c.applySession(session);
          return c;
        }),
        kvStoreProvider.overrideWithValue(kv),
        interruptedOpsProvider.overrideWithValue(interruptedOps),
      ],
      child: const MergelioApp(),
    ),
  );

  // Reveal the window only after the first frame is painted, so the user never
  // sees an empty native window.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Every connected display, with the primary one flagged. An empty list means
/// the platform could not tell us, in which case the window is simply centred.
Future<List<DisplayInfo>> _connectedDisplays() async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    final primary = await screenRetriever.getPrimaryDisplay();
    return [
      for (final d in displays)
        DisplayInfo(
          size: d.size,
          visiblePosition: d.visiblePosition,
          visibleSize: d.visibleSize,
          scaleFactor: d.scaleFactor?.toDouble(),
          isPrimary: d.id == primary.id,
        ),
    ];
  } catch (e, st) {
    appLog.error('display query failed, centring window', e, st, 'startup');
    return const [];
  }
}

/// Self-contained fallback shown by [ErrorWidget.builder] when a widget subtree
/// throws. Deliberately theme-independent so it renders even if theming failed.
class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF0B0D12),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong rendering this view.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFEAECF3), fontSize: 13),
          ),
        ),
      ),
    );
  }
}
