import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/lfs.dart';

const _oid = '4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393';
const _valid =
    'version https://git-lfs.github.com/spec/v1\n'
    'oid sha256:$_oid\n'
    'size 12345\n';

void main() {
  test('parses a valid pointer', () {
    expect(parseLfsPointer(_valid), const LfsPointer(oid: _oid, size: 12345));
  });

  test('accepts CRLF and a missing trailing newline', () {
    expect(parseLfsPointer(_valid.replaceAll('\n', '\r\n'))?.size, 12345);
    expect(parseLfsPointer(_valid.trimRight())?.oid, _oid);
  });

  test('accepts extension keys that sort before oid', () {
    const withExt =
        'version https://git-lfs.github.com/spec/v1\n'
        'ext-0-foo sha256:$_oid\n'
        'oid sha256:$_oid\n'
        'size 1\n';
    expect(parseLfsPointer(withExt)?.size, 1);
  });

  group('rejects', () {
    final cases = <String, String>{
      'wrong version line': _valid.replaceFirst('/v1', '/v2'),
      'version not first':
          'oid sha256:$_oid\n'
          'version https://git-lfs.github.com/spec/v1\nsize 1\n',
      'uppercase oid': _valid.replaceFirst(_oid, _oid.toUpperCase()),
      'short oid': _valid.replaceFirst(_oid, _oid.substring(1)),
      'non-sha256 oid': _valid.replaceFirst('sha256:', 'sha1:'),
      'negative size': _valid.replaceFirst('12345', '-1'),
      'leading zero size': _valid.replaceFirst('12345', '012345'),
      'missing size':
          'version https://git-lfs.github.com/spec/v1\n'
          'oid sha256:$_oid\n',
      'missing oid': 'version https://git-lfs.github.com/spec/v1\nsize 1\n',
      'unsorted keys':
          'version https://git-lfs.github.com/spec/v1\n'
          'size 1\noid sha256:$_oid\n',
      'duplicate key': '${_valid}size 2\n',
      'repeated version key':
          '${_valid}version https://git-lfs.github.com/spec/v1\n',
      'line without value': '${_valid}zz\n',
      'blank line inside': _valid.replaceFirst('\noid', '\n\noid'),
      'empty': '',
      'over 1024 bytes': '$_valid${'x' * 1024}',
    };
    cases.forEach((name, text) {
      test(name, () => expect(parseLfsPointer(text), isNull));
    });
  });
}
