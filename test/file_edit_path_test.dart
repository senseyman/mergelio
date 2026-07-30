import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/file_edit.dart';

void main() {
  group('isRepoRelativePath', () {
    test('accepts ordinary repo-relative paths', () {
      expect(isRepoRelativePath('a.txt'), isTrue);
      expect(isRepoRelativePath('lib/src/a.dart'), isTrue);
      expect(isRepoRelativePath('a b/c d.txt'), isTrue);
      expect(isRepoRelativePath('..a/b..'), isTrue); // dots inside names
      expect(isRepoRelativePath('a/.hidden'), isTrue);
    });

    test('rejects paths that escape or leave the repository', () {
      expect(isRepoRelativePath(''), isFalse);
      expect(isRepoRelativePath('../outside.txt'), isFalse);
      expect(isRepoRelativePath('a/../../outside.txt'), isFalse);
      expect(isRepoRelativePath('a/..'), isFalse);
      expect(isRepoRelativePath(r'a\..\outside.txt'), isFalse);
      expect(isRepoRelativePath('/etc/passwd'), isFalse);
      expect(isRepoRelativePath(r'\server\share'), isFalse);
      expect(isRepoRelativePath(r'C:\Windows\a.txt'), isFalse);
      expect(isRepoRelativePath('C:/Windows/a.txt'), isFalse);
    });
  });
}
