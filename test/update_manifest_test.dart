import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/update/app_version.dart';
import 'package:mergelio/domain/update/update_manifest.dart';

const _json = '''
{
  "schema": 1,
  "version": "1.5.0",
  "build": 16,
  "published": "2026-08-26T12:00:00Z",
  "notes_url": "https://example.invalid/notes",
  "artifacts": {
    "macos-arm64": {
      "url": "https://example.invalid/app.zip",
      "sha256": "abc123",
      "size": 42
    }
  }
}
''';

void main() {
  test('reads a manifest', () {
    final m = UpdateManifest.fromJson(
      jsonDecode(_json) as Map<String, dynamic>,
    );
    expect(m.schema, 1);
    expect(m.appVersion, AppVersion.parse('1.5.0+16'));
    expect(m.notesUrl, 'https://example.invalid/notes');
    expect(m.artifacts['macos-arm64']!.sha256, 'abc123');
    expect(m.artifacts['macos-arm64']!.size, 42);
  });

  test('survives a platform key it has never heard of', () {
    final raw = jsonDecode(_json) as Map<String, dynamic>;
    (raw['artifacts'] as Map<String, dynamic>)['plan9-riscv'] = {
      'url': 'https://example.invalid/x',
      'sha256': 'ff',
      'size': 1,
    };
    final m = UpdateManifest.fromJson(raw);
    expect(m.artifacts.containsKey('plan9-riscv'), isTrue);
    expect(m.artifacts['macos-arm64'], isNotNull);
  });

  test('rejects a manifest missing a required field', () {
    final raw = jsonDecode(_json) as Map<String, dynamic>..remove('version');
    expect(() => UpdateManifest.fromJson(raw), throwsA(anything));
  });
}
