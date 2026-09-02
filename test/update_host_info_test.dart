import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/update/host_info.dart';

void main() {
  test('reads the architecture out of the Dart version string', () {
    expect(
      archFromDartVersion('3.12.2 (stable) (Tue Jun 3 2026) on "macos_arm64"'),
      'arm64',
    );
    expect(
      archFromDartVersion('3.12.2 (stable) (Tue) on "windows_x64"'),
      'x64',
    );
    expect(archFromDartVersion('3.12.2 (stable) on "linux_x64"'), 'x64');
  });

  test('returns an empty string when the shape is unfamiliar', () {
    expect(archFromDartVersion('3.12.2'), '');
    expect(archFromDartVersion(''), '');
  });
}
