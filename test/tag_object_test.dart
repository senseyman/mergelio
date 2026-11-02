import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/tag_object.dart';

void main() {
  const raw =
      'object 1111111111111111111111111111111111111111\n'
      'type commit\n'
      'tag v1\n'
      'tagger Tester <t@example.com> 1700000000 +0000\n'
      '\n'
      'release\n'
      'tag v1\n';

  test('renames the tag header and nothing else', () {
    expect(
      renameTagObject(raw, 'v2'),
      'object 1111111111111111111111111111111111111111\n'
      'type commit\n'
      'tag v2\n'
      'tagger Tester <t@example.com> 1700000000 +0000\n'
      '\n'
      'release\n'
      // A message line that happens to look like a header stays as written.
      'tag v1\n',
    );
  });

  test('a tag object without a tag header is rejected', () {
    expect(
      () => renameTagObject('object 11\ntype commit\n\nmsg\n', 'v2'),
      throwsFormatException,
    );
  });

  group('isSignedTagObject', () {
    const head = 'object 11\ntype commit\ntag v1\ntagger T <t@e> 1 +0000\n';
    for (final marker in [
      '-----BEGIN PGP SIGNATURE-----',
      '-----BEGIN PGP MESSAGE-----',
      '-----BEGIN SSH SIGNATURE-----',
      '-----BEGIN SIGNED MESSAGE-----',
    ]) {
      test('a body signed with $marker', () {
        expect(
          isSignedTagObject('$head\nmsg\n$marker\nAAAA\n-----END\n'),
          true,
        );
      });
    }

    test('a signature header over the other hash counts', () {
      expect(isSignedTagObject('${head}gpgsig-sha256 x\n y\n\nmsg\n'), true);
    });

    test('a plain message does not, nor a marker mid-line', () {
      expect(isSignedTagObject('$head\nmsg\n'), false);
      expect(
        isSignedTagObject('$head\nsee -----BEGIN PGP SIGNATURE-----\n'),
        false,
      );
    });
  });

  test('a tag header after the blank line does not count', () {
    expect(
      () => renameTagObject('object 11\ntype commit\n\ntag v1\n', 'v2'),
      throwsFormatException,
    );
  });
}
