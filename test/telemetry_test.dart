import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/telemetry.dart';

class _FakeSink implements TelemetrySink {
  final events = <(String, Map<String, Object?>)>[];
  @override
  void send(String event, Map<String, Object?> properties) =>
      events.add((event, properties));
}

void main() {
  test('disabled reporter never sends', () {
    final sink = _FakeSink();
    const TelemetryReporter(enabled: false).event('open');
    TelemetryReporter(enabled: false, sink: sink).event('open');
    expect(sink.events, isEmpty);
  });

  test('enabled reporter sends events through the sink', () {
    final sink = _FakeSink();
    TelemetryReporter(
      enabled: true,
      sink: sink,
    ).event('commit', properties: {'files': 3});
    expect(sink.events.single.$1, 'commit');
    expect(sink.events.single.$2['files'], 3);
  });

  group('scrub redacts identifying data', () {
    test('emails, urls and SSH remotes', () {
      expect(TelemetryReporter.scrub('me@example.com'), '<email>');
      expect(TelemetryReporter.scrub('https://github.com/x/y'), '<url>');
      // SSH remote must fully redact org/repo, not leak it past the email rule.
      expect(
        TelemetryReporter.scrub('git@github.com:acme/secret-repo.git'),
        '<remote>',
      );
    });

    test('absolute paths — POSIX, Windows drive, and UNC/WSL', () {
      expect(TelemetryReporter.scrub('/Users/me/code/repo'), '<path>');
      expect(TelemetryReporter.scrub(r'C:\Users\me\repo'), '<path>');
      expect(TelemetryReporter.scrub(r'\\wsl$\Ubuntu\home\alice\x'), '<path>');
      expect(
        TelemetryReporter.scrub('opened /Users/me/x now'),
        'opened <path> now',
      );
    });

    test('non-identifying values with slashes pass through unchanged', () {
      // Relative refs and shortcuts are not paths → not redacted (data quality).
      expect(TelemetryReporter.scrub('feature/a/b'), 'feature/a/b');
      expect(TelemetryReporter.scrub('ctrl/shift/k'), 'ctrl/shift/k');
      // A 40-char commit SHA is not PII → kept for analytics.
      final sha = 'a' * 40;
      expect(TelemetryReporter.scrub(sha), sha);
    });

    test('non-sensitive scalars pass through', () {
      expect(TelemetryReporter.scrub(42), 42);
      expect(TelemetryReporter.scrub(true), true);
      expect(TelemetryReporter.scrub('rebase'), 'rebase');
    });
  });

  test('enabled reporter scrubs property values before sending', () {
    final sink = _FakeSink();
    TelemetryReporter(enabled: true, sink: sink).event(
      'open',
      properties: {'repo': '/Users/me/secret-project', 'count': 5},
    );
    final props = sink.events.single.$2;
    expect(props['repo'], '<path>');
    expect(props['count'], 5);
  });
}
