import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';

void main() {
  group('stepConflict', () {
    test('with nothing selected, next lands on the first conflict', () {
      expect(stepConflict(3, null, forward: true), 0);
    });

    test('with nothing selected, previous lands on the last conflict', () {
      expect(stepConflict(3, null, forward: false), 2);
    });

    test('moves one conflict either way', () {
      expect(stepConflict(3, 0, forward: true), 1);
      expect(stepConflict(3, 2, forward: false), 1);
    });

    test('wraps around at both ends', () {
      expect(stepConflict(3, 2, forward: true), 0);
      expect(stepConflict(3, 0, forward: false), 2);
    });

    test('a single conflict stays put', () {
      expect(stepConflict(1, 0, forward: true), 0);
      expect(stepConflict(1, 0, forward: false), 0);
    });

    test('no conflicts means nowhere to go', () {
      expect(stepConflict(0, null, forward: true), isNull);
      expect(stepConflict(0, null, forward: false), isNull);
    });
  });
}
