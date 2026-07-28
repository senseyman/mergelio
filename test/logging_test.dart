import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';

/// Logging must survive a crash and must not grow without bound: every line is
/// appended immediately (no buffer to lose), and the file rotates once it hits
/// its size cap so a long-running session can never fill the user's disk.
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mergelio_log_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('formatLogLine', () {
    test('renders an ISO timestamp, a padded level and the message', () {
      final line = formatLogLine(
        DateTime.utc(2026, 7, 28, 9, 40, 12, 345),
        LogLevel.info,
        'window restored',
      );

      expect(line, '2026-07-28T09:40:12.345Z INFO  window restored');
    });

    test('truncates sub-millisecond precision so columns stay fixed', () {
      final line = formatLogLine(
        DateTime.utc(2026, 7, 28, 9, 3, 42, 97, 420),
        LogLevel.info,
        'launching',
      );

      expect(line, '2026-07-28T09:03:42.097Z INFO  launching');
    });

    test('keeps the columns aligned across levels', () {
      final ts = DateTime.utc(2026, 7, 28);
      final widths = {
        for (final level in LogLevel.values)
          level: formatLogLine(ts, level, 'x').indexOf('x'),
      };

      expect(widths.values.toSet(), hasLength(1));
    });

    test('indents continuation lines so multi-line entries stay readable', () {
      final line = formatLogLine(
        DateTime.utc(2026, 7, 28),
        LogLevel.error,
        'boom\n#0 main\n#1 run',
      );

      expect(line.split('\n').skip(1), everyElement(startsWith('    ')));
    });
  });

  group('FileLogSink', () {
    test('creates the log directory and appends each line', () {
      final sink = FileLogSink(Directory('${dir.path}/logs'));

      sink.write('first');
      sink.write('second');

      expect(sink.file.readAsStringSync(), 'first\nsecond\n');
    });

    test('reopens an existing file without truncating it', () {
      FileLogSink(dir).write('before restart');
      FileLogSink(dir).write('after restart');

      expect(
        FileLogSink(dir).file.readAsStringSync(),
        'before restart\nafter restart\n',
      );
    });

    test('rotates once the file passes its size cap', () {
      final sink = FileLogSink(dir, maxBytes: 32);

      sink.write('a' * 40);
      sink.write('fresh');

      expect(sink.file.readAsStringSync(), 'fresh\n');
      expect(
        File('${dir.path}/mergelio.1.log').readAsStringSync(),
        '${'a' * 40}\n',
      );
    });

    test('shifts older archives up and drops the oldest past the cap', () {
      final sink = FileLogSink(dir, maxBytes: 8, keep: 2);

      sink.write('oldest!!!');
      sink.write('middle!!!');
      sink.write('newest!!!');
      sink.write('current');

      expect(
        File('${dir.path}/mergelio.1.log').readAsStringSync(),
        startsWith('newest'),
      );
      expect(
        File('${dir.path}/mergelio.2.log').readAsStringSync(),
        startsWith('middle'),
      );
      expect(File('${dir.path}/mergelio.3.log').existsSync(), isFalse);
    });

    test('swallows I/O failures so logging can never crash the app', () {
      final sink = FileLogSink(dir);
      dir.deleteSync(recursive: true);
      File(dir.path).writeAsStringSync('not a directory');

      expect(() => sink.write('doomed'), returnsNormally);
    });
  });

  group('AppLogger', () {
    test('drops entries below the configured level', () {
      final sink = _RecordingSink();
      final log = AppLogger(sink: sink, level: LogLevel.warn);

      log.debug('noise');
      log.info('noise');
      log.warn('kept');
      log.error('kept');

      expect(sink.lines, hasLength(2));
      expect(sink.lines.first, contains('kept'));
    });

    test('writes the error and its stack trace as one entry', () {
      final sink = _RecordingSink();
      final log = AppLogger(sink: sink, level: LogLevel.debug);

      log.error(
        'clone failed',
        StateError('no remote'),
        StackTrace.fromString('#0 frame'),
      );

      expect(sink.lines, hasLength(1));
      expect(sink.lines.single, contains('clone failed'));
      expect(sink.lines.single, contains('no remote'));
      expect(sink.lines.single, contains('#0 frame'));
    });

    test('tags entries with the caller-supplied scope', () {
      final sink = _RecordingSink();
      final log = AppLogger(sink: sink, level: LogLevel.debug);

      log.info('pull done', scope: 'git');

      expect(sink.lines.single, contains('[git] pull done'));
    });

    test('stamps entries with the injected clock', () {
      final sink = _RecordingSink();
      final log = AppLogger(
        sink: sink,
        level: LogLevel.debug,
        now: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      log.info('hello');

      expect(sink.lines.single, startsWith('2026-01-02T03:04:05.000Z INFO'));
    });
  });

  group('debugPrint bridge', () {
    test('mirrors debugPrint output into the log at info level', () {
      final sink = _RecordingSink();
      final log = AppLogger(sink: sink, level: LogLevel.debug);
      final forwarded = <String>[];

      final bridge = debugPrintBridge(log, (message, {wrapWidth}) {
        forwarded.add(message ?? '');
      });
      bridge('recents: save failed', wrapWidth: null);

      expect(sink.lines.single, contains('recents: save failed'));
      expect(forwarded, ['recents: save failed']);
    });

    test('ignores a null message instead of logging an empty line', () {
      final sink = _RecordingSink();
      final bridge = debugPrintBridge(
        AppLogger(sink: sink, level: LogLevel.debug),
        (message, {wrapWidth}) {},
      );

      bridge(null, wrapWidth: null);

      expect(sink.lines, isEmpty);
    });
  });
}

class _RecordingSink implements LogSink {
  final List<String> lines = [];

  @override
  void write(String line) => lines.add(line);
}
