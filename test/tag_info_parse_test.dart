import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/tag_info.dart';

/// One `for-each-ref` record as [kTagInfoFormat] writes it.
String _rec(List<String> f) => '\x1e${f.join('\x00')}\n';

void main() {
  group('parseTagInfos', () {
    test('an annotated tag carries tagger, date and message', () {
      final tags = parseTagInfos(
        _rec([
          'v1.0',
          'tag',
          'Tester',
          't@example.com',
          '2026-10-19T11:30:24+01:00',
          'Release 1.0',
          'Second paragraph.\n',
        ]),
      );
      expect(tags, hasLength(1));
      final t = tags.single;
      expect(t.name, 'v1.0');
      expect(t.annotated, isTrue);
      expect(t.tagger, 'Tester');
      expect(t.taggerEmail, 't@example.com');
      expect(t.date, DateTime.utc(2026, 10, 19, 10, 30, 24));
      expect(t.dateOffset, const Duration(hours: 1));
      expect(t.subject, 'Release 1.0');
      expect(t.body, 'Second paragraph.');
    });

    test('a lightweight tag ignores the commit message git fills in', () {
      final t = parseTagInfos(
        _rec(['lw', 'commit', '', '', '', 'commit subject', 'commit body']),
      ).single;
      expect(t.name, 'lw');
      expect(t.annotated, isFalse);
      expect(t.subject, '');
      expect(t.body, '');
      expect(t.date, isNull);
    });

    test('several records, multi-line bodies and empty output', () {
      final tags = parseTagInfos(
        _rec([
              'a',
              'tag',
              'A',
              'a@x',
              '2026-01-01T00:00:00+00:00',
              's',
              'l1\nl2\n',
            ]) +
            _rec(['b', 'commit', '', '', '', 'x', '']),
      );
      expect(tags.map((t) => t.name), ['a', 'b']);
      expect(tags.first.body, 'l1\nl2');
      expect(parseTagInfos(''), isEmpty);
      expect(parseTagInfos('\n'), isEmpty);
    });

    test('a malformed record is skipped, not thrown on', () {
      expect(parseTagInfos('\x1egarbage\n'), isEmpty);
    });
  });

  group('parseTagSigning', () {
    // `config --get-regexp -z`: `key\nvalue\0`, or `key\0` for a bare key.
    String cfg(Map<String, String?> kv) => [
      for (final e in kv.entries)
        e.value == null ? '${e.key}\x00' : '${e.key}\n${e.value}\x00',
    ].join();

    test('nothing set: no key, not signed by default', () {
      final s = parseTagSigning('');
      expect(s.key, isNull);
      expect(s.byDefault, isFalse);
    });

    test('either signing setting on signs by default', () {
      expect(parseTagSigning(cfg({'tag.gpgsign': 'true'})).byDefault, isTrue);
      expect(
        parseTagSigning(cfg({'commit.gpgsign': 'true'})).byDefault,
        isTrue,
      );
    });

    test('an explicit off for tags wins over the commit setting', () {
      expect(
        parseTagSigning(cfg({'commit.gpgsign': 'true', 'tag.gpgsign': 'false'}))
            .byDefault,
        isFalse,
      );
    });

    test('reads booleans the way git does', () {
      for (final v in ['yes', 'on', '1', 'TRUE', '7']) {
        expect(
          parseTagSigning(cfg({'tag.gpgsign': v})).byDefault,
          isTrue,
          reason: v,
        );
      }
      for (final v in ['no', 'off', '0', 'false', '', 'bogus']) {
        expect(
          parseTagSigning(cfg({'tag.gpgsign': v})).byDefault,
          isFalse,
          reason: v,
        );
      }
      // A bare `gpgsign` line with no `=` is true.
      expect(parseTagSigning(cfg({'commit.gpgsign': null})).byDefault, isTrue);
    });

    test('the last value of a key wins, as in git', () {
      final s = parseTagSigning(
        cfg({'tag.gpgsign': 'true'}) + cfg({'tag.gpgsign': 'false'}),
      );
      expect(s.byDefault, isFalse);
    });

    test('the configured key, spaces inside kept', () {
      expect(
        parseTagSigning(cfg({'user.signingkey': '~/my key.pub'})).key,
        '~/my key.pub',
      );
      expect(parseTagSigning(cfg({'user.signingkey': ''})).key, isNull);
    });
  });
}
