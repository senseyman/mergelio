import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/kv_store.dart';
import 'data/settings_repository.dart';
import 'state/operation_journal.dart';
import 'state/profiles.dart';
import 'state/recents.dart';
import 'state/settings.dart';
import 'state/settings_controller.dart';
import 'state/workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Error boundary: log framework and async errors instead of taking the whole
  // app down, and show a contained fallback in place of a failed subtree.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('uncaught framework error: ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('uncaught async error: $error\n$stack');
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
  var restoredTabs = const <String>[];
  var interruptedOps = const <String>[];
  try {
    settings = await settingsRepo.load();
    recents = await recentsRepo.load();
    profiles = await ProfilesController.load(kv);
    restoredTabs = await WorkspaceController.restorePaths(kv);
    // Scan each restored repo's journal: an op still pending means the app
    // stopped mid-operation last time, so warn the user on launch.
    final notices = <String>[];
    for (final path in restoredTabs) {
      final j = OperationJournal(kv, path);
      await j.load();
      for (final r in j.interrupted) {
        notices.add('${path.split('/').last}: ${r.label}');
      }
    }
    interruptedOps = notices;
  } catch (e, st) {
    debugPrint('startup: state load failed, using defaults: $e\n$st');
  }

  const options = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(960, 600),
    center: true,
    title: 'Mergelio',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options);

  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => SettingsController(settingsRepo, settings),
        ),
        recentsProvider.overrideWith(
          (ref) => RecentsController(recentsRepo, recents),
        ),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(kv, profiles),
        ),
        workspaceProvider.overrideWith((ref) {
          final c = WorkspaceController(kv);
          for (final p in restoredTabs) {
            c.openRepo(p);
          }
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
