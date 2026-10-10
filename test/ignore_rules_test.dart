import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/ignore.dart';

void main() {
  group('ignoreRule', () {
    test('anchors a single file to its path', () {
      expect(ignoreRule('build/out.log', IgnoreScope.file), '/build/out.log');
      expect(ignoreRule('a.txt', IgnoreScope.file), '/a.txt');
    });

    test('ignores every file sharing the extension, at any depth', () {
      expect(ignoreRule('src/app.log', IgnoreScope.extension), '*.log');
      expect(ignoreRule('a.tar.gz', IgnoreScope.extension), '*.gz');
    });

    test('has no extension rule for files without one', () {
      expect(ignoreRule('Makefile', IgnoreScope.extension), isNull);
      expect(ignoreRule('cfg/.env', IgnoreScope.extension), isNull);
    });

    test('anchors the containing folder with a trailing slash', () {
      expect(ignoreRule('a/b/c.txt', IgnoreScope.folder), '/a/b/');
    });

    test('has no folder rule for a file at the base itself', () {
      expect(ignoreRule('c.txt', IgnoreScope.folder), isNull);
      expect(
        ignoreRule('pkg/c.txt', IgnoreScope.folder, baseDir: 'pkg'),
        isNull,
      );
    });

    test('writes rules relative to a nested .gitignore', () {
      expect(
        ignoreRule('pkg/gen/x.dart', IgnoreScope.file, baseDir: 'pkg'),
        '/gen/x.dart',
      );
      expect(
        ignoreRule('pkg/gen/x.dart', IgnoreScope.folder, baseDir: 'pkg'),
        '/gen/',
      );
      expect(
        ignoreRule('pkg/gen/x.dart', IgnoreScope.extension, baseDir: 'pkg'),
        '*.dart',
      );
    });

    test('refuses a path outside the base', () {
      expect(
        ignoreRule('other/x.txt', IgnoreScope.file, baseDir: 'pkg'),
        isNull,
      );
      expect(
        ignoreRule('pkgx/x.txt', IgnoreScope.file, baseDir: 'pkg'),
        isNull,
      );
    });

    test('escapes glob characters so they match literally', () {
      expect(
        ignoreRule(r'a[1]*?\b.txt', IgnoreScope.file),
        r'/a\[1]\*\?\\b.txt',
      );
      expect(ignoreRule('x.[ch]', IgnoreScope.extension), r'*.\[ch]');
    });

    test('anchoring neutralises a leading # or !', () {
      expect(ignoreRule('#notes', IgnoreScope.file), '/#notes');
      expect(ignoreRule('!keep', IgnoreScope.file), '/!keep');
    });

    test('escapes trailing spaces, which git would otherwise drop', () {
      expect(ignoreRule('name  ', IgnoreScope.file), r'/name\ \ ');
    });

    test('escapes only trailing spaces, leaving other whitespace as is', () {
      expect(ignoreRule('name\t', IgnoreScope.file), '/name\t');
      expect(ignoreRule('name\t ', IgnoreScope.file), '/name\t\\ ');
    });

    test('refuses paths a single line cannot hold', () {
      expect(ignoreRule('a\nb', IgnoreScope.file), isNull);
      expect(ignoreRule('a\rb', IgnoreScope.file), isNull);
      expect(ignoreRule('', IgnoreScope.file), isNull);
    });
  });

  group('appendIgnoreRule', () {
    test('appends to an empty file', () {
      expect(appendIgnoreRule('', '/a.txt'), '/a.txt\n');
    });

    test('keeps everything already there', () {
      expect(appendIgnoreRule('build/\n', '*.log'), 'build/\n*.log\n');
    });

    test('adds the missing final newline first', () {
      expect(appendIgnoreRule('build/', '*.log'), 'build/\n*.log\n');
      expect(appendIgnoreRule('build/\r\n', '*.log'), 'build/\r\n*.log\n');
    });

    test('reports a rule that is already present', () {
      expect(appendIgnoreRule('x\n*.log\ny\n', '*.log'), isNull);
      expect(appendIgnoreRule('*.log', '*.log'), isNull);
      expect(appendIgnoreRule('*.log\r\n', '*.log'), isNull);
    });

    test('matches a rule ending in an escaped space exactly', () {
      expect(appendIgnoreRule('/name\\ \n', r'/name\ '), isNull);
      expect(appendIgnoreRule('/name\\\n', r'/name\ '), '/name\\\n/name\\ \n');
    });

    test('does not mistake a longer line for the rule', () {
      expect(appendIgnoreRule('*.logs\n', '*.log'), '*.logs\n*.log\n');
    });
  });

  test('ancestorDirs lists the closest directory first, root excluded', () {
    expect(ancestorDirs('a/b/c.txt'), ['a/b', 'a']);
    expect(ancestorDirs('c.txt'), isEmpty);
  });
}
