import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/signature.dart';

import 'support/hermetic_git.dart';

/// Creating, reading back and restoring tags against real git, signed with a
/// throwaway SSH key (no agent or keyring needed). Global and system config
/// are switched off so the developer's own `tag.gpgSign` cannot leak in.
void main() {
  const svc = HermeticGit();
  bool probe() {
    try {
      Process.runSync('ssh-keygen', ['-?']);
      return true;
    } catch (_) {
      return false;
    }
  }

  final hasSshKeygen = probe();

  late Directory dir;
  late String repo;
  late String key;

  Future<String> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_tags_');
    repo = '${dir.path}/r';
    await Directory(repo).create();
    key = '${dir.path}/key';
    if (hasSshKeygen) {
      final k = await Process.run('ssh-keygen', [
        '-q', '-t', 'ed25519', '-N', '', '-C', 't@example.com', '-f', key, //
      ]);
      if (k.exitCode != 0) throw StateError('ssh-keygen: ${k.stderr}');
      final pub = (await File('$key.pub').readAsString()).trim();
      await File('${dir.path}/allowed').writeAsString('t@example.com $pub\n');
    }
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'gpg.format', 'ssh']);
    await g(['config', 'gpg.ssh.allowedSignersFile', '${dir.path}/allowed']);
    await g(['commit', '-q', '--allow-empty', '-m', 'base']);
  });

  tearDown(() => dir.delete(recursive: true));

  GitReader reader() => GitReader(svc, repo);
  GitWriter writer() => GitWriter(svc, repo);

  Future<String> objectType(String tag) =>
      g(['cat-file', '-t', 'refs/tags/$tag']);

  group('createTag', () {
    test('signs with the configured key', () async {
      await g(['config', 'user.signingkey', '$key.pub']);
      await writer().createTag('v1', message: 'release', sign: true);
      expect((await reader().verifyTag('v1')).state, SignatureState.good);
    }, skip: hasSshKeygen ? false : 'ssh-keygen not available');

    test('signs with the key it is given over the configured one', () async {
      await g(['config', 'user.signingkey', '/nonexistent.pub']);
      await writer().createTag(
        'v1',
        message: 'release',
        sign: true,
        signingKey: '$key.pub',
      );
      expect((await reader().verifyTag('v1')).state, SignatureState.good);
    }, skip: hasSshKeygen ? false : 'ssh-keygen not available');

    test(
      'signing with an empty message falls back to an annotated tag',
      () async {
        await g(['config', 'user.signingkey', '$key.pub']);
        await writer().createTag('v1', sign: true);
        expect(await objectType('v1'), 'tag');
        expect((await reader().verifyTag('v1')).state, SignatureState.good);
      },
      skip: hasSshKeygen ? false : 'ssh-keygen not available',
    );

    test('tag.gpgSign cannot break or sign an unsigned request', () async {
      await g(['config', 'user.signingkey', '$key.pub']);
      await g(['config', 'tag.gpgSign', 'true']);
      await writer().createTag('lw');
      await writer().createTag('ann', message: 'plain');
      expect(await objectType('lw'), 'commit');
      expect(await objectType('ann'), 'tag');
      expect(
        await g(['cat-file', '-p', 'refs/tags/ann']),
        isNot(contains('SIGNATURE')),
      );
    }, skip: hasSshKeygen ? false : 'ssh-keygen not available');

    test('the given identity becomes the tagger', () async {
      await writer().createTag(
        'v1',
        message: 'm',
        authorName: 'Profile Person',
        authorEmail: 'p@example.com',
      );
      final t = (await reader().tagInfos('HEAD')).single;
      expect(t.tagger, 'Profile Person');
      expect(t.taggerEmail, 'p@example.com');
    });

    test('a signing failure surfaces as a GitException', () async {
      await expectLater(
        writer().createTag(
          'v1',
          message: 'm',
          sign: true,
          signingKey: '/nonexistent.pub',
        ),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('restoreTag', () {
    test('brings back the very tag object, signature included', () async {
      await g(['config', 'user.signingkey', '$key.pub']);
      await g(['config', 'tag.gpgSign', 'true']);
      await g(['tag', '-s', '-m', 'release', 'v1']);
      final obj = await g(['rev-parse', 'refs/tags/v1']);
      await writer().deleteTag('v1');
      await writer().restoreTag('v1', obj);
      expect(await g(['rev-parse', 'refs/tags/v1']), obj);
      expect((await reader().verifyTag('v1')).state, SignatureState.good);
    }, skip: hasSshKeygen ? false : 'ssh-keygen not available');

    test('refuses to overwrite a tag that exists again', () async {
      await g(['tag', 'v1']);
      final obj = await g(['rev-parse', 'HEAD']);
      await g(['commit', '-q', '--allow-empty', '-m', 'next']);
      await g(['tag', '-f', 'v1']);
      await expectLater(
        writer().restoreTag('v1', obj),
        throwsA(isA<GitException>()),
      );
      expect(await g(['rev-parse', 'refs/tags/v1']), isNot(obj));
    });
  });

  group('tagInfos', () {
    test('reads every tag on a commit, without signature text', () async {
      await g(['config', 'user.signingkey', '$key.pub']);
      await g(['tag', 'lw']);
      await g(['tag', '-a', '-m', 'Plain subject', '-m', 'Plain body', 'ann']);
      await g(['tag', '-s', '-m', 'Signed subject', 'sig']);
      await g(['commit', '-q', '--allow-empty', '-m', 'later']);
      await g(['tag', 'elsewhere']);

      final tags = await reader().tagInfos(await g(['rev-parse', 'HEAD~1']));
      final byName = {for (final t in tags) t.name: t};
      expect(byName.keys, unorderedEquals(['lw', 'ann', 'sig']));
      expect(byName['lw']!.annotated, isFalse);
      expect(byName['ann']!.subject, 'Plain subject');
      expect(byName['ann']!.body, 'Plain body');
      expect(byName['ann']!.tagger, 'Tester');
      expect(byName['ann']!.date, isNotNull);
      expect(byName['sig']!.subject, 'Signed subject');
      expect(byName['sig']!.body, isEmpty);
    }, skip: hasSshKeygen ? false : 'ssh-keygen not available');
  });

  group('tagSigning', () {
    test('nothing configured: no key, not signed by default', () async {
      final s = await reader().tagSigning();
      expect(s.key, isNull);
      expect(s.byDefault, isFalse);
    });

    test('follows commit.gpgsign, in any spelling git accepts', () async {
      await g(['config', 'user.signingkey', '$key.pub']);
      await g(['config', 'commit.gpgsign', 'yes']);
      final s = await reader().tagSigning();
      expect(s.key, '$key.pub');
      expect(s.byDefault, isTrue);
    });

    test('a config git cannot read is an error, not "nothing set"', () async {
      await File('$repo/.git/config')
          .writeAsString('[broken\n', mode: FileMode.append);
      await expectLater(reader().tagSigning(), throwsA(isA<GitException>()));
    });
  });
}
