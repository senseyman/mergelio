import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/update/platform_target.dart';

void main() {
  test('maps the shipped desktop targets', () {
    expect(platformKey(os: 'macos', arch: 'arm64'), 'macos-arm64');
    expect(platformKey(os: 'windows', arch: 'x64'), 'windows-x64');
  });

  test('picks the Linux package format from os-release', () {
    const fedora = 'ID=fedora\nID_LIKE=rhel fedora\n';
    const ubuntu = 'ID=ubuntu\nID_LIKE=debian\n';
    expect(
      platformKey(os: 'linux', arch: 'x64', osRelease: fedora),
      'linux-x64-rpm',
    );
    expect(
      platformKey(os: 'linux', arch: 'x64', osRelease: ubuntu),
      'linux-x64-deb',
    );
  });

  test('falls back to deb when os-release says nothing useful', () {
    expect(platformKey(os: 'linux', arch: 'x64'), 'linux-x64-deb');
  });

  test('returns null for a target that has no build', () {
    expect(platformKey(os: 'macos', arch: 'x64'), isNull);
    expect(platformKey(os: 'windows', arch: 'arm64'), isNull);
    expect(platformKey(os: 'fuchsia', arch: 'x64'), isNull);
  });
}
