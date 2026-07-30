import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Severity of a log entry, ordered from most to least verbose. The logger
/// keeps entries at or above its configured level and drops the rest.
enum LogLevel { debug, info, warn, error }

extension on LogLevel {
  /// Fixed-width label so every line's message column starts at the same
  /// offset — a log read in a plain editor stays scannable.
  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO ',
    LogLevel.warn => 'WARN ',
    LogLevel.error => 'ERROR',
  };
}

/// Renders one entry as `<utc timestamp> <LEVEL> <message>`. Continuation lines
/// (stack traces, multi-line errors) are indented so they read as part of the
/// entry above them rather than as separate entries.
String formatLogLine(DateTime when, LogLevel level, String message) {
  // `DateTime.now()` carries microseconds, which `toIso8601String` would render
  // as a wider field and knock the columns out of line; millisecond resolution
  // is plenty for reading a log.
  final utc = when.toUtc();
  final stamp = DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  ).toIso8601String();
  final head = '${stamp.endsWith('Z') ? stamp : '${stamp}Z'} ${level.label} ';
  final lines = message.split('\n');
  return [
    '$head${lines.first}',
    for (final rest in lines.skip(1)) '    $rest',
  ].join('\n');
}

/// Destination for formatted log lines. Abstract so tests can capture entries
/// without touching the filesystem.
abstract class LogSink {
  void write(String line);
}

/// Discards everything. The default until [initFileLogging] wires a real sink,
/// so call sites can log during startup without a null check.
class NullLogSink implements LogSink {
  const NullLogSink();

  @override
  void write(String line) {}
}

/// Appends entries to `mergelio.log`, rotating to numbered archives once the
/// live file passes [maxBytes] and keeping at most [keep] of them.
///
/// Each line is flushed on write: a crash is exactly the case the log exists
/// for, so buffering would drop the entries that matter most. Every filesystem
/// error is swallowed — logging must never be the reason the app fails.
class FileLogSink implements LogSink {
  static const _base = 'mergelio';

  final Directory dir;
  final int maxBytes;
  final int keep;

  FileLogSink(this.dir, {this.maxBytes = 2 * 1024 * 1024, this.keep = 3});

  /// The live log file. Archives sit beside it as `mergelio.1.log`, `.2`, …
  /// with `.1` always the most recently rotated.
  File get file => File(p.join(dir.path, '$_base.log'));

  File _archive(int index) => File(p.join(dir.path, '$_base.$index.log'));

  @override
  void write(String line) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final target = file;
      if (target.existsSync() && target.lengthSync() >= maxBytes) {
        _rotate(target);
      }
      target.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // A log that cannot be written is not worth an exception.
    }
  }

  void _rotate(File current) {
    final oldest = _archive(keep);
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = keep - 1; i >= 1; i--) {
      final archive = _archive(i);
      if (archive.existsSync()) archive.renameSync(_archive(i + 1).path);
    }
    current.renameSync(_archive(1).path);
  }
}

/// Filters entries by level, stamps them and hands them to a [LogSink].
class AppLogger {
  final LogSink sink;
  final LogLevel level;
  final DateTime Function() now;

  AppLogger({
    required this.sink,
    this.level = LogLevel.info,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  void debug(String message, {String? scope}) =>
      log(LogLevel.debug, message, scope: scope);

  void info(String message, {String? scope}) =>
      log(LogLevel.info, message, scope: scope);

  void warn(String message, {String? scope}) =>
      log(LogLevel.warn, message, scope: scope);

  /// Records a failure together with its cause and stack, so a bug report can
  /// be reconstructed from the log alone.
  void error(
    String message, [
    Object? error,
    StackTrace? stack,
    String? scope,
  ]) => log(LogLevel.error, message, error: error, stack: stack, scope: scope);

  /// Runs [op] as a named action, logging one line when it starts and one
  /// when it ends with the elapsed wall-clock time. A failure is logged with
  /// its cause and rethrown, so call sites keep their own error handling.
  Future<T> timed<T>(
    String label,
    Future<T> Function() op, {
    String? scope,
  }) async {
    final started = now();
    info('$label started', scope: scope);
    try {
      final result = await op();
      final ms = now().difference(started).inMilliseconds;
      info('$label completed in ${ms}ms', scope: scope);
      return result;
    } on Object catch (e) {
      final ms = now().difference(started).inMilliseconds;
      error('$label failed after ${ms}ms', e, null, scope);
      rethrow;
    }
  }

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stack,
    String? scope,
  }) {
    if (level.index < this.level.index) return;
    final buffer = StringBuffer(scope == null ? message : '[$scope] $message');
    if (error != null) buffer.write('\n$error');
    if (stack != null) buffer.write('\n${stack.toString().trimRight()}');
    sink.write(formatLogLine(now(), level, buffer.toString()));
  }
}

/// The app-wide logger. Starts inert and is replaced by [initFileLogging] once
/// the log directory is known, so imports never depend on startup order.
AppLogger appLog = AppLogger(sink: const NullLogSink());

/// Path of the live log file, or null while logging is inert — used by the UI
/// to offer (or hide) a way to reach the log.
String? get logFilePath {
  final sink = appLog.sink;
  return sink is FileLogSink ? sink.file.path : null;
}

/// Wraps [next] (normally the original `debugPrint`) so everything the app
/// already prints is mirrored into the log file, keeping existing call sites
/// untouched while still producing a durable record.
DebugPrintCallback debugPrintBridge(AppLogger logger, DebugPrintCallback next) {
  return (String? message, {int? wrapWidth}) {
    if (message != null) logger.info(message);
    next(message, wrapWidth: wrapWidth);
  };
}

/// Points [appLog] at `<app support>/logs/mergelio.log` and routes `debugPrint`
/// through it. Falls back to the inert logger if the directory is unavailable,
/// so a read-only or missing support directory cannot block startup.
Future<AppLogger> initFileLogging({LogLevel? level}) async {
  try {
    final support = await getApplicationSupportDirectory();
    appLog = AppLogger(
      sink: FileLogSink(Directory(p.join(support.path, 'logs'))),
      level: level ?? (kReleaseMode ? LogLevel.info : LogLevel.debug),
    );
    debugPrint = debugPrintBridge(appLog, debugPrint);
  } catch (_) {
    // Keep the inert logger; the app must start regardless.
  }
  return appLog;
}
