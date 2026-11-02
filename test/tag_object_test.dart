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

  test('a tag header after the blank line does not count', () {
    expect(
      () => renameTagObject('object 11\ntype commit\n\ntag v1\n', 'v2'),
      throwsFormatException,
    );
  });
}
