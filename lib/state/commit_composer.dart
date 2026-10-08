import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kv_store.dart';
import '../domain/git/commit_message.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import 'operation_journal.dart';

/// How the commit composer behaves in one repository.
class ComposerPrefs {
  /// A message template kept in Mergelio. Wins over git's own when set.
  final String template;

  /// Whether the composer offers the Conventional Commits type/scope row.
  final bool conventional;

  /// The subject length the meter measures against.
  final int subjectLimit;

  const ComposerPrefs({
    this.template = '',
    this.conventional = false,
    this.subjectLimit = 72,
  });

  ComposerPrefs copyWith({
    String? template,
    bool? conventional,
    int? subjectLimit,
  }) => ComposerPrefs(
    template: template ?? this.template,
    conventional: conventional ?? this.conventional,
    subjectLimit: subjectLimit ?? this.subjectLimit,
  );

  Map<String, Object> toJson() => {
    'template': template,
    'conventional': conventional,
    'subjectLimit': subjectLimit,
  };

  factory ComposerPrefs.fromJson(Map<String, dynamic> j) => ComposerPrefs(
    template: j['template'] as String? ?? '',
    conventional: j['conventional'] as bool? ?? false,
    subjectLimit: j['subjectLimit'] as int? ?? 72,
  );
}

/// A message the user started and walked away from, kept for its branch.
class ComposerDraft {
  final String summary;
  final String description;
  final String coauthors;
  final String refs;
  final String fixes;
  final String type;
  final String scope;
  final bool breaking;

  const ComposerDraft({
    this.summary = '',
    this.description = '',
    this.coauthors = '',
    this.refs = '',
    this.fixes = '',
    this.type = '',
    this.scope = '',
    this.breaking = false,
  });

  /// Nothing typed. The Conventional Commits row alone — type, scope,
  /// breaking — is not a message worth bringing back.
  bool get isEmpty => [
    summary,
    description,
    coauthors,
    refs,
    fixes,
  ].every((s) => s.trim().isEmpty);

  Map<String, Object> toJson() => {
    'summary': summary,
    'description': description,
    'coauthors': coauthors,
    'refs': refs,
    'fixes': fixes,
    'type': type,
    'scope': scope,
    'breaking': breaking,
  };

  factory ComposerDraft.fromJson(Map<String, dynamic> j) => ComposerDraft(
    summary: j['summary'] as String? ?? '',
    description: j['description'] as String? ?? '',
    coauthors: j['coauthors'] as String? ?? '',
    refs: j['refs'] as String? ?? '',
    fixes: j['fixes'] as String? ?? '',
    type: j['type'] as String? ?? '',
    scope: j['scope'] as String? ?? '',
    breaking: j['breaking'] as bool? ?? false,
  );
}

/// The composer's persisted state for one repository: its prefs, a draft per
/// branch and the messages recently committed from it. Anything unreadable
/// in the store reads as nothing stored.
class ComposerStore {
  final KeyValueStore _kv;
  final String _repo;
  ComposerStore(this._kv, this._repo);

  String get _prefsKey => 'composer:prefs:$_repo';
  String get _draftsKey => 'composer:drafts:$_repo';
  String get _recentKey => 'composer:recent:$_repo';

  Future<Object?> _read(String key) async {
    final raw = await _kv.get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<ComposerPrefs> prefs() async {
    final j = await _read(_prefsKey);
    return j is Map<String, dynamic>
        ? ComposerPrefs.fromJson(j)
        : const ComposerPrefs();
  }

  Future<void> savePrefs(ComposerPrefs prefs) =>
      _kv.put(_prefsKey, jsonEncode(prefs.toJson()));

  Future<Map<String, dynamic>> _drafts() async {
    final j = await _read(_draftsKey);
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }

  Future<ComposerDraft?> draft(String branch) async {
    final j = (await _drafts())[branch];
    return j is Map<String, dynamic> ? ComposerDraft.fromJson(j) : null;
  }

  /// Keeps [draft] for [branch]; an empty one forgets the branch's draft.
  Future<void> saveDraft(String branch, ComposerDraft draft) async {
    final all = await _drafts();
    if (draft.isEmpty) {
      if (all.remove(branch) == null) return;
    } else {
      all[branch] = draft.toJson();
    }
    await _kv.put(_draftsKey, jsonEncode(all));
  }

  Future<List<String>> recent() async {
    final j = await _read(_recentKey);
    return j is List
        ? [
            for (final m in j)
              if (m is String) m,
          ]
        : const [];
  }

  Future<void> remember(String message) async =>
      _kv.put(_recentKey, jsonEncode(pushRecent(await recent(), message)));
}

final composerStoreProvider = Provider.family<ComposerStore, String>(
  (ref, path) => ComposerStore(ref.watch(kvStoreProvider), path),
);

/// The prefs for one repository, read from the store once and written back on
/// every [update].
class ComposerPrefsController extends StateNotifier<ComposerPrefs> {
  final ComposerStore _store;

  /// Completes once the stored prefs have replaced the defaults.
  late final Future<void> loaded;

  ComposerPrefsController(this._store) : super(const ComposerPrefs()) {
    loaded = _store.prefs().then(
      (p) {
        if (mounted) state = p;
      },
      // Unreadable prefs leave the defaults in place rather than every later
      // update failing on the same error.
      onError: (Object _) {},
    );
  }

  // The last update queued; the next one starts only once it is done.
  Future<void> _pending = Future.value();

  /// Applies [change] to the latest prefs. Updates run one after another, so
  /// two made back to back each see the other's result instead of both
  /// starting from the same state and the later write dropping the earlier.
  Future<void> update(ComposerPrefs Function(ComposerPrefs) change) {
    final run = _pending.then((_) async {
      await loaded;
      final next = change(state);
      // Stored before it is announced, so a listener that reads the store
      // back sees the new value.
      await _store.savePrefs(next);
      if (mounted) state = next;
    });
    // A failed save must not wedge every later update behind it.
    _pending = run.catchError((Object _) {});
    return run;
  }
}

final composerPrefsProvider =
    StateNotifierProvider.family<
      ComposerPrefsController,
      ComposerPrefs,
      String
    >(
      (ref, path) =>
          ComposerPrefsController(ref.watch(composerStoreProvider(path))),
    );

/// The template the composer starts an empty message from, comments already
/// stripped: the one saved in Mergelio, else git's own.
final commitTemplateProvider = FutureProvider.autoDispose
    .family<({String text, String commentChar}), String>((ref, path) async {
      // Re-read when the saved template changes.
      ref.watch(composerPrefsProvider(path).select((p) => p.template));
      final saved =
          (await ref.read(composerStoreProvider(path)).prefs()).template;
      final git = await GitReader(
        ref.watch(gitServiceProvider),
        path,
      ).commitTemplate();
      final raw = saved.trim().isNotEmpty ? saved : git.template;
      return (
        text: stripCommentLines(raw, commentChar: git.commentChar),
        commentChar: git.commentChar,
      );
    });
