import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/state/diagnostics.dart';

/// Riverpod turns a thrown error into `AsyncValue.error`, which reaches neither
/// `FlutterError.onError` nor `PlatformDispatcher.onError` — so without an
/// observer a failed provider leaves no trace at all, and the UI's "could not
/// read" message is the only evidence the user ever gets.
void main() {
  late _RecordingSink sink;
  late LoggingProviderObserver observer;

  setUp(() {
    sink = _RecordingSink();
    observer = LoggingProviderObserver(
      AppLogger(sink: sink, level: LogLevel.debug),
    );
  });

  test('logs a failing provider with its error and stack', () async {
    final failing = FutureProvider<int>(
      (ref) => throw StateError('git exploded'),
      name: 'repoData',
    );
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    await container.read(failing.future).catchError((_) => 0);

    expect(sink.lines, hasLength(1));
    expect(sink.lines.single, contains('ERROR'));
    expect(sink.lines.single, contains('repoData'));
    expect(sink.lines.single, contains('git exploded'));
  });

  test(
    'names the family argument so the failing repo is identifiable',
    () async {
      final family = FutureProvider.family<int, String>(
        (ref, arg) => throw StateError('boom'),
        name: 'repoData',
      );
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      await container
          .read(family('/Users/me/proj').future)
          .catchError((_) => 0);

      expect(sink.lines.single, contains('/Users/me/proj'));
    },
  );

  test('says nothing while providers succeed', () async {
    final ok = FutureProvider<int>((ref) async => 1, name: 'fine');
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    await container.read(ok.future);

    expect(sink.lines, isEmpty);
  });
}

class _RecordingSink implements LogSink {
  final List<String> lines = [];

  @override
  void write(String line) => lines.add(line);
}
