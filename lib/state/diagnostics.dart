import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/reveal.dart';

/// Records provider failures in the log.
///
/// Riverpod turns a thrown error into an `AsyncValue.error` that the UI renders
/// as a message — it never reaches `FlutterError.onError` or
/// `PlatformDispatcher.onError`. Without this observer, a repository that fails
/// to load leaves nothing behind to diagnose.
class LoggingProviderObserver extends ProviderObserver {
  final AppLogger? _logger;

  const LoggingProviderObserver([this._logger]);

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    final name = provider.name ?? provider.runtimeType.toString();
    final argument = provider.argument;
    final target = argument == null ? name : '$name($argument)';
    (_logger ?? appLog).error('$target failed', error, stackTrace, 'provider');
  }
}

/// Where the live log file sits, or null when file logging never started (a
/// read-only support directory, or a test).
final logFilePathProvider = Provider<String?>((ref) => logFilePath);

/// Opens a path in the platform file manager. Injected so widgets can be tested
/// without launching Finder/Explorer.
final revealProvider = Provider<Future<void> Function(String)>(
  (ref) =>
      (path) => revealInFileManager(path),
);
