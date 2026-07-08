import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_controller.dart';

/// Where anonymised telemetry events go. Kept abstract so the app ships without
/// a wired backend — a concrete HTTP sink can be provided later without
/// touching call sites. No sink means events are dropped.
abstract class TelemetrySink {
  void send(String event, Map<String, Object?> properties);
}

/// Opt-in, privacy-preserving telemetry. Events are dropped entirely unless the
/// user has turned telemetry on; when on, property values are scrubbed of
/// personally-identifying data (file paths, emails, URLs, long tokens) before
/// they ever reach the sink.
class TelemetryReporter {
  final bool enabled;
  final TelemetrySink? sink;

  const TelemetryReporter({required this.enabled, this.sink});

  void event(String name, {Map<String, Object?> properties = const {}}) {
    if (!enabled || sink == null) return;
    sink!.send(name, {
      for (final e in properties.entries) e.key: scrub(e.value),
    });
  }

  /// Redacts values that could identify a user: emails, remote URLs, SSH
  /// remotes, and absolute filesystem paths (POSIX, Windows drive, and UNC —
  /// including `\\wsl$` shares). Redaction is anchored so that identifying data
  /// embedded mid-string is caught, while non-identifying values that merely
  /// contain slashes (a keyboard shortcut like `ctrl/shift/k`, a branch ref
  /// like `feature/a/b`, or a commit SHA) pass through unchanged.
  ///
  /// Callers must not put secrets (API keys, tokens) in property values; those
  /// are not part of the emitted schema and are not redacted here.
  static Object? scrub(Object? value) {
    if (value is! String) return value;
    var s = value;
    // SSH remotes (user@host:org/repo) — before the email rule, which would
    // otherwise consume the `user@host` and leave the org/repo exposed.
    s = s.replaceAll(RegExp(r'\b[\w.+-]+@[\w.-]+:[^\s]+'), '<remote>');
    s = s.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>');
    s = s.replaceAll(RegExp(r'[a-zA-Z][\w+.-]*://[^\s]+'), '<url>');
    // Absolute paths, anchored at string start or after whitespace so relative
    // slash-lists (feature/a/b, ctrl/shift/k) are left intact:
    //   POSIX /a/b · Windows X:\a\b or X:/a/b · UNC \\host\share (incl \\wsl$).
    String pathRepl(Match m) => '${m[1]}<path>';
    s = s.replaceAllMapped(RegExp(r'(^|\s)\\\\[^\s]+'), pathRepl);
    s = s.replaceAllMapped(RegExp(r'(^|\s)[A-Za-z]:[\\/][^\s]*'), pathRepl);
    s = s.replaceAllMapped(RegExp(r'(^|\s)/[^\s]+'), pathRepl);
    return s;
  }
}

/// Telemetry gated on the current opt-in setting. Rebuilds when the toggle
/// changes; ships without a sink (events dropped) until a backend is wired.
final telemetryProvider = Provider<TelemetryReporter>((ref) {
  final enabled = ref.watch(settingsProvider.select((s) => s.telemetryEnabled));
  return TelemetryReporter(enabled: enabled);
});
