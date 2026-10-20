import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/repo_config.dart';

/// One record as `config --show-scope --show-origin -z --get-regexp` prints
/// it; a null [value] is a bare key.
String _rec(String scope, String origin, String key, [String? value]) =>
    '$scope\x00$origin\x00${value == null ? key : '$key\n$value'}\x00';

void main() {
  group('parseScopedConfig', () {
    test('reads scope, origin, key and value in git order', () {
      final c = parseScopedConfig(
        _rec('global', 'file:/home/u/.gitconfig', 'user.name', 'Glob Al') +
            _rec('local', 'file:.git/config', 'user.name', 'Lo Cal'),
      );
      expect(c.entries, hasLength(2));
      final e = c.entries.first;
      expect(e.scope, ConfigScope.global);
      expect(e.origin, '/home/u/.gitconfig');
      expect(e.key, 'user.name');
      expect(e.value, 'Glob Al');
    });

    test('the last occurrence is the one in effect', () {
      final c = parseScopedConfig(
        _rec('global', 'file:g', 'pull.rebase', 'true') +
            _rec('local', 'file:.git/config', 'pull.rebase', 'false'),
      );
      expect(c.effective('pull.rebase')!.value, 'false');
      expect(c.effective('pull.rebase')!.scope, ConfigScope.local);
      expect(c.inScope('pull.rebase', ConfigScope.global)!.value, 'true');
      expect(c.inScope('pull.rebase', ConfigScope.system), isNull);
      expect(c.effective('fetch.prune'), isNull);
    });

    test('keys match whatever case the caller spells them in', () {
      final c = parseScopedConfig(
        _rec('local', 'file:x', 'push.autosetupremote', 'true'),
      );
      expect(c.effective('push.autoSetupRemote')!.value, 'true');
    });

    test('a bare key has no value, and values may hold newlines', () {
      final c = parseScopedConfig(
        _rec('local', 'file:x', 'rerere.enabled') +
            _rec('local', 'file:x', 'user.name', 'two\nlines'),
      );
      expect(c.effective('rerere.enabled')!.value, isNull);
      expect(c.effective('user.name')!.value, 'two\nlines');
    });

    test('every scope git names, unknown ones kept', () {
      final c = parseScopedConfig(
        _rec('system', 'file:/etc/gitconfig', 'a.b', '1') +
            _rec('worktree', 'file:.git/config.worktree', 'a.c', '1') +
            _rec('command', 'command line:', 'a.d', '1') +
            _rec('someday', 'blob:x', 'a.e', '1'),
      );
      expect(c.entries.map((e) => e.scope), [
        ConfigScope.system,
        ConfigScope.worktree,
        ConfigScope.command,
        ConfigScope.unknown,
      ]);
      // Only file origins have a path to show.
      expect(c.entries[2].origin, isNull);
    });

    test('empty output and a truncated tail', () {
      expect(parseScopedConfig('').entries, isEmpty);
      expect(parseScopedConfig('local\x00file:x').entries, isEmpty);
    });
  });

  group('normaliseConfigValue', () {
    final bool = repoConfigKey('rerere.enabled');
    final rebase = repoConfigKey('pull.rebase');
    final crlf = repoConfigKey('core.autocrlf');

    test('booleans read the way git reads them', () {
      for (final v in ['true', 'yes', 'on', '1', 'TRUE', null]) {
        expect(normaliseConfigValue(bool, v), 'true', reason: '$v');
      }
      for (final v in ['false', 'no', 'off', '0', '']) {
        expect(normaliseConfigValue(bool, v), 'false', reason: v);
      }
      expect(normaliseConfigValue(bool, 'bogus'), isNull);
    });

    test('pull.rebase takes its own words besides booleans', () {
      expect(normaliseConfigValue(rebase, 'yes'), 'true');
      expect(normaliseConfigValue(rebase, 'merges'), 'merges');
      expect(normaliseConfigValue(rebase, 'm'), 'merges');
      // Not offered as a choice: no chip, shown raw.
      expect(normaliseConfigValue(rebase, 'interactive'), isNull);
    });

    test('core.autocrlf takes input besides booleans', () {
      expect(normaliseConfigValue(crlf, 'input'), 'input');
      expect(normaliseConfigValue(crlf, 'off'), 'false');
    });

    test('every key the tab offers is in the read pattern', () {
      for (final k in kRepoConfigKeys) {
        expect(
          RegExp(kRepoConfigPattern).hasMatch(k.key.toLowerCase()),
          isTrue,
          reason: k.key,
        );
      }
      expect(RegExp(kRepoConfigPattern).hasMatch('user.namex'), isFalse);
    });
  });
}
