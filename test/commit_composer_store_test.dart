import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/commit_composer.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/window_focus.dart';

/// Answers `git config` reads from a map; every other call is empty.
class _ConfigGit implements GitService {
  final Map<String, String> config;
  _ConfigGit(this.config);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'config') {
      final v = config[args.last];
      return v == null ? const GitResult(1, '', '') : GitResult(0, v, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Holds a listener while reading, as the composer does, so the auto-disposed
/// provider is not dropped mid-load.
Future<({String text, String commentChar})> _template(ProviderContainer c) {
  final sub = c.listen(commitTemplateProvider('/r'), (_, _) {});
  addTearDown(sub.close);
  return c.read(commitTemplateProvider('/r').future);
}

/// The first write fails, as a briefly locked database would; the rest work.
class _FailOnceStore implements KeyValueStore {
  final _inner = InMemoryKeyValueStore();
  var _failed = false;

  @override
  Future<String?> get(String key) => _inner.get(key);

  @override
  Future<void> put(String key, String value) async {
    if (!_failed) {
      _failed = true;
      throw StateError('database is locked');
    }
    await _inner.put(key, value);
  }
}

/// Reads fail, writes succeed: a store whose stored value is unreadable.
class _UnreadableStore implements KeyValueStore {
  @override
  Future<String?> get(String key) async => throw StateError('disk I/O');

  @override
  Future<void> put(String key, String value) async {}
}

void main() {
  group('ComposerStore', () {
    late InMemoryKeyValueStore kv;
    setUp(() => kv = InMemoryKeyValueStore());

    test('prefs default when nothing is stored', () async {
      final p = await ComposerStore(kv, '/r').prefs();
      expect(p.template, '');
      expect(p.conventional, isFalse);
      expect(p.subjectLimit, 72);
    });

    test('prefs round-trip, per repository', () async {
      await ComposerStore(kv, '/r').savePrefs(
        const ComposerPrefs(
          template: 'T',
          conventional: true,
          subjectLimit: 50,
        ),
      );
      final p = await ComposerStore(kv, '/r').prefs();
      expect(p.template, 'T');
      expect(p.conventional, isTrue);
      expect(p.subjectLimit, 50);
      expect((await ComposerStore(kv, '/other').prefs()).template, '');
    });

    test('corrupt prefs fall back to defaults', () async {
      await kv.put('composer:prefs:/r', '{not json');
      expect((await ComposerStore(kv, '/r').prefs()).subjectLimit, 72);
    });

    test('drafts are kept per branch', () async {
      final s = ComposerStore(kv, '/r');
      await s.saveDraft(
        'main',
        const ComposerDraft(summary: 'on main', refs: '#3', breaking: true),
      );
      await s.saveDraft('topic', const ComposerDraft(summary: 'on topic'));

      final main = await ComposerStore(kv, '/r').draft('main');
      expect(main?.summary, 'on main');
      expect(main?.refs, '#3');
      expect(main?.breaking, isTrue);
      expect((await s.draft('topic'))?.summary, 'on topic');
      expect(await s.draft('other'), isNull);
    });

    test('saving an empty draft removes it', () async {
      final s = ComposerStore(kv, '/r');
      await s.saveDraft('main', const ComposerDraft(summary: 'x'));
      await s.saveDraft('main', const ComposerDraft());
      expect(await s.draft('main'), isNull);
    });

    test('the type row alone is not worth keeping as a draft', () {
      expect(const ComposerDraft(type: 'feat').isEmpty, isTrue);
      expect(
        const ComposerDraft(type: 'feat', scope: 'ui', breaking: true).isEmpty,
        isTrue,
      );
      expect(const ComposerDraft(fixes: '#1').isEmpty, isFalse);
    });

    test('drafts saved at the same moment are all kept', () async {
      final s = ComposerStore(kv, '/r');
      await Future.wait([
        s.saveDraft('a', const ComposerDraft(summary: 'on a')),
        s.saveDraft('b', const ComposerDraft(summary: 'on b')),
        s.saveDraft('c', const ComposerDraft(summary: 'on c')),
      ]);
      expect((await s.draft('a'))?.summary, 'on a');
      expect((await s.draft('b'))?.summary, 'on b');
      expect((await s.draft('c'))?.summary, 'on c');
    });

    test('messages remembered at the same moment are all kept', () async {
      final s = ComposerStore(kv, '/r');
      await Future.wait([s.remember('one'), s.remember('two')]);
      expect(await s.recent(), unorderedEquals(['one', 'two']));
    });

    test('a failed write does not hold up the ones after it', () async {
      final s = ComposerStore(_FailOnceStore(), '/r');
      await expectLater(
        s.saveDraft('a', const ComposerDraft(summary: 'x')),
        throwsStateError,
      );
      await s.saveDraft('b', const ComposerDraft(summary: 'y'));
      expect((await s.draft('b'))?.summary, 'y');
    });

    test('recent messages are remembered newest first, capped at 10', () async {
      final s = ComposerStore(kv, '/r');
      for (var i = 0; i < 12; i++) {
        await s.remember('m$i');
      }
      await s.remember('m5');
      final recent = await ComposerStore(kv, '/r').recent();
      expect(recent.first, 'm5');
      expect(recent, hasLength(10));
      expect(recent.where((m) => m == 'm5'), hasLength(1));
    });
  });

  group('commitTemplateProvider', () {
    ProviderContainer container(
      Map<String, String> config,
      InMemoryKeyValueStore kv,
    ) {
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
          gitServiceProvider.overrideWithValue(_ConfigGit(config)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the template saved in Mergelio wins over git config', () async {
      final kv = InMemoryKeyValueStore();
      await ComposerStore(
        kv,
        '/r',
      ).savePrefs(const ComposerPrefs(template: 'saved\n# hint'));
      final c = container({}, kv);
      final t = await _template(c);
      expect(t.text, 'saved');
    });

    test('the template is read again when the window regains focus', () async {
      final dir = await Directory.systemTemp.createTemp('mergelio_tpl_focus_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/.gitmessage')..writeAsStringSync('first');
      final c = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          gitServiceProvider.overrideWithValue(_ConfigGit({})),
        ],
      );
      addTearDown(c.dispose);
      final provider = commitTemplateProvider(dir.path);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect((await c.read(provider.future)).text, 'first');

      // Edited in another app while Mergelio was in the background.
      file.writeAsStringSync('second');
      c.read(windowFocusedProvider.notifier).state = false;
      expect((await c.read(provider.future)).text, 'first');
      c.read(windowFocusedProvider.notifier).state = true;
      expect((await c.read(provider.future)).text, 'second');
    });

    test('no template anywhere is empty', () async {
      final c = container({}, InMemoryKeyValueStore());
      final t = await _template(c);
      expect(t.text, '');
    });
  });

  group('ComposerPrefsController', () {
    test('prefs that cannot be read leave the defaults usable', () async {
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(_UnreadableStore())],
      );
      addTearDown(c.dispose);
      final sub = c.listen(composerPrefsProvider('/r'), (_, _) {});
      addTearDown(sub.close);
      final prefs = c.read(composerPrefsProvider('/r').notifier);
      await prefs.loaded;
      await prefs.update((p) => p.copyWith(subjectLimit: 50));
      expect(c.read(composerPrefsProvider('/r')).subjectLimit, 50);
    });

    test('updates made back to back are both kept', () async {
      final kv = InMemoryKeyValueStore();
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(composerPrefsProvider('/r'), (_, _) {});
      addTearDown(sub.close);
      final prefs = c.read(composerPrefsProvider('/r').notifier);
      await Future.wait([
        prefs.update((p) => p.copyWith(subjectLimit: 50)),
        prefs.update((p) => p.copyWith(conventional: true)),
      ]);
      final state = c.read(composerPrefsProvider('/r'));
      expect(state.subjectLimit, 50);
      expect(state.conventional, isTrue);
      final stored = await ComposerStore(kv, '/r').prefs();
      expect(stored.subjectLimit, 50);
      expect(stored.conventional, isTrue);
    });

    test('loads the stored prefs and persists updates', () async {
      final kv = InMemoryKeyValueStore();
      await ComposerStore(
        kv,
        '/r',
      ).savePrefs(const ComposerPrefs(subjectLimit: 100));
      final c = ProviderContainer(
        overrides: [kvStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(c.dispose);
      final sub = c.listen(composerPrefsProvider('/r'), (_, _) {});
      addTearDown(sub.close);
      await c.read(composerPrefsProvider('/r').notifier).loaded;
      expect(c.read(composerPrefsProvider('/r')).subjectLimit, 100);

      await c
          .read(composerPrefsProvider('/r').notifier)
          .update((p) => p.copyWith(conventional: true));
      expect(c.read(composerPrefsProvider('/r')).conventional, isTrue);
      expect((await ComposerStore(kv, '/r').prefs()).conventional, isTrue);
      expect((await ComposerStore(kv, '/r').prefs()).subjectLimit, 100);
    });
  });
}
