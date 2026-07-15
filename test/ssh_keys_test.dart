import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/ssh_keys.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_ssh_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('lists only .pub files, sorted', () async {
    File('${dir.path}/id_rsa.pub').writeAsStringSync('ssh-rsa AAAA me@host\n');
    File(
      '${dir.path}/id_ed25519.pub',
    ).writeAsStringSync('ssh-ed25519 BBBB me@host\n');
    File('${dir.path}/id_rsa').writeAsStringSync('PRIVATE'); // must be ignored
    File('${dir.path}/known_hosts').writeAsStringSync('x');

    final keys = await SshKeys(dir: dir.path).list();
    expect(keys.map((k) => k.name), ['id_ed25519', 'id_rsa']);
    expect(keys.first.publicKey, 'ssh-ed25519 BBBB me@host');
  });

  test('empty or missing directory lists nothing', () async {
    expect(await SshKeys(dir: '${dir.path}/nope').list(), isEmpty);
  });

  test('generate creates a usable ed25519 key pair', () async {
    final keys = SshKeys(dir: dir.path);
    final k = await keys.generate('test_key', comment: 'mergelio-test');
    expect(k.publicKey, startsWith('ssh-ed25519 '));
    expect(k.publicKey, contains('mergelio-test'));
    // Both halves exist; the new key shows up in the listing.
    expect(File('${dir.path}/test_key').existsSync(), isTrue);
    expect(File('${dir.path}/test_key.pub').existsSync(), isTrue);
    expect((await keys.list()).map((x) => x.name), contains('test_key'));
    // Refuses to overwrite.
    expect(
      () => keys.generate('test_key', comment: 'x'),
      throwsA(isA<StateError>()),
    );
  });

  test('generate rejects names that could escape ~/.ssh', () async {
    final keys = SshKeys(dir: dir.path);
    for (final bad in ['../evil', 'a/b', r'a\b', '..', '']) {
      expect(
        () => keys.generate(bad, comment: 'x'),
        throwsA(isA<StateError>()),
        reason: 'name "$bad" must be rejected',
      );
    }
  });
}
