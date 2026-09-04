import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/update/app_version.dart';

void main() {
  test('orders by numeric component, not lexically', () {
    expect(AppVersion.parse('1.10.0') > AppVersion.parse('1.9.9'), isTrue);
  });

  test('breaks a version tie with the build number', () {
    expect(AppVersion.parse('1.4.1+16') > AppVersion.parse('1.4.1+15'), isTrue);
  });

  test('ranks a pre-release below its release', () {
    expect(AppVersion.parse('1.5.0-rc.1') < AppVersion.parse('1.5.0'), isTrue);
  });

  test('treats a missing build number as zero', () {
    expect(AppVersion.parse('1.5.0').build, 0);
    expect(AppVersion.parse('1.5.0'), AppVersion.parse('1.5.0+0'));
  });

  test('round-trips through toString', () {
    expect(AppVersion.parse('1.4.1+15').toString(), '1.4.1+15');
    expect(AppVersion.parse('1.4.1').toString(), '1.4.1');
  });

  test('returns null for input it cannot read', () {
    expect(AppVersion.tryParse('not a version'), isNull);
    expect(AppVersion.tryParse('1.4.1+nightly'), isNull);
    expect(AppVersion.tryParse(''), isNull);
  });
}
