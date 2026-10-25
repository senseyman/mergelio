// Which files read as Markdown, and where a link or image source inside one
// leads: out to the web, to another file in the repository, or nowhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/markdown_links.dart';

String? repoPath(MarkdownTarget? t) => t is RepoFileTarget ? t.path : null;

void main() {
  group('isMarkdownPath', () {
    test('a .md file is Markdown, whatever the case', () {
      expect(isMarkdownPath('README.md'), isTrue);
      expect(isMarkdownPath('docs/Guide.MD'), isTrue);
    });

    test('other extensions are not', () {
      expect(isMarkdownPath('notes.markdown'), isFalse);
      expect(isMarkdownPath('page.mdx'), isFalse);
      expect(isMarkdownPath('md'), isFalse);
      expect(isMarkdownPath('lib/md.dart'), isFalse);
    });
  });

  group('resolveMarkdownHref', () {
    test('http and https leave for the web', () {
      final t = resolveMarkdownHref('https://example.com/a?b=1', from: 'x.md');
      expect(t, isA<WebTarget>());
      expect((t as WebTarget).uri.toString(), 'https://example.com/a?b=1');
      expect(
        resolveMarkdownHref('http://e.com', from: 'x.md'),
        isA<WebTarget>(),
      );
    });

    test('any other scheme leads nowhere', () {
      for (final href in [
        'mailto:a@b.c',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:image/png;base64,AAAA',
        '//cdn.example.com/x.png',
      ]) {
        expect(resolveMarkdownHref(href, from: 'x.md'), isNull, reason: href);
      }
    });

    test('nothing, an empty link and an in-page anchor lead nowhere', () {
      expect(resolveMarkdownHref(null, from: 'x.md'), isNull);
      expect(resolveMarkdownHref('', from: 'x.md'), isNull);
      expect(resolveMarkdownHref('#install', from: 'x.md'), isNull);
      expect(resolveMarkdownHref('?q=1', from: 'x.md'), isNull);
    });

    test('a relative path resolves beside the document', () {
      expect(
        repoPath(resolveMarkdownHref('b.md', from: 'docs/a.md')),
        'docs/b.md',
      );
      expect(
        repoPath(resolveMarkdownHref('./img/x.png', from: 'docs/a.md')),
        'docs/img/x.png',
      );
      expect(
        repoPath(resolveMarkdownHref('../LICENSE', from: 'docs/a.md')),
        'LICENSE',
      );
      expect(
        repoPath(resolveMarkdownHref('CHANGELOG.md', from: 'README.md')),
        'CHANGELOG.md',
      );
    });

    test('a leading slash resolves from the repository root', () {
      expect(
        repoPath(resolveMarkdownHref('/docs/x.md', from: 'a/b/c.md')),
        'docs/x.md',
      );
    });

    test('anchor and query are dropped from a file link', () {
      expect(
        repoPath(resolveMarkdownHref('b.md#usage', from: 'docs/a.md')),
        'docs/b.md',
      );
      expect(
        repoPath(resolveMarkdownHref('b.md?plain=1', from: 'a.md')),
        'b.md',
      );
    });

    test('percent escapes are decoded', () {
      expect(
        repoPath(resolveMarkdownHref('my%20notes.md', from: 'a.md')),
        'my notes.md',
      );
    });

    test('a path climbing out of the repository leads nowhere', () {
      expect(resolveMarkdownHref('../x.md', from: 'a.md'), isNull);
      expect(resolveMarkdownHref('../../x.md', from: 'docs/a.md'), isNull);
      expect(resolveMarkdownHref('/../x.md', from: 'a.md'), isNull);
    });

    test('a link to a folder leads nowhere', () {
      expect(resolveMarkdownHref('docs/', from: 'a.md'), isNull);
      expect(resolveMarkdownHref('.', from: 'a.md'), isNull);
      expect(resolveMarkdownHref('..', from: 'docs/a.md'), isNull);
    });
  });
}
