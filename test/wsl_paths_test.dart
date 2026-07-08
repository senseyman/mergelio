import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/wsl_paths.dart';

void main() {
  test('recognises WSL UNC paths (both prefixes)', () {
    expect(isWslPath(r'\\wsl$\Ubuntu\home\me\repo'), isTrue);
    expect(isWslPath(r'\\wsl.localhost\Debian\srv'), isTrue);
    expect(isWslPath(r'C:\Users\me\repo'), isFalse);
    expect(isWslPath('/home/me/repo'), isFalse);
  });

  test('extracts the distro name', () {
    expect(wslDistro(r'\\wsl$\Ubuntu\home\me'), 'Ubuntu');
    expect(wslDistro(r'\\wsl.localhost\Debian-12\srv'), 'Debian-12');
    expect(wslDistro(r'C:\x'), isNull);
  });

  test('prettifies a WSL path for display', () {
    expect(
      displayPath(r'\\wsl$\Ubuntu\home\me\repo'),
      'wsl:Ubuntu/home/me/repo',
    );
    expect(displayPath(r'C:\Users\me'), r'C:\Users\me'); // unchanged
    // Bare share with no distro: returned as-is, never "wsl:null".
    expect(displayPath(r'\\wsl$\'), r'\\wsl$\');
  });

  test('converts Windows drive paths ↔ /mnt', () {
    expect(windowsToMnt(r'C:\Users\me\repo'), '/mnt/c/Users/me/repo');
    expect(mntToWindows('/mnt/c/Users/me'), r'C:\Users\me');
    // Round-trip.
    expect(mntToWindows(windowsToMnt(r'D:\a\b')), r'D:\a\b');
    // Non-matching inputs pass through.
    expect(windowsToMnt('/home/me'), '/home/me');
    expect(mntToWindows(r'C:\x'), r'C:\x');
  });
}
