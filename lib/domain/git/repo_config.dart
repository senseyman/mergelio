/// The handful of git config keys the Repository preferences edit: what each
/// is set to in every scope, where that comes from, and which value git
/// actually uses.
library;

/// Where a config value was read from, as `--show-scope` names it.
enum ConfigScope { system, global, local, worktree, command, unknown }

ConfigScope _scopeOf(String s) => switch (s) {
  'system' => ConfigScope.system,
  'global' => ConfigScope.global,
  'local' => ConfigScope.local,
  'worktree' => ConfigScope.worktree,
  'command' => ConfigScope.command,
  _ => ConfigScope.unknown,
};

/// One occurrence of a key in one config file.
class ConfigEntry {
  final ConfigScope scope;

  /// The file it was read from; null when it did not come from a file (the
  /// command line, a blob).
  final String? origin;

  /// Lowercased, as git prints it.
  final String key;

  /// Null for a bare key (`[rerere] enabled`), which git reads as true.
  final String? value;

  const ConfigEntry({
    required this.scope,
    required this.origin,
    required this.key,
    required this.value,
  });
}

/// Every occurrence of the keys read, in the order git reads them, so the
/// last one of a key is the one in effect.
class RepoConfig {
  final List<ConfigEntry> entries;
  const RepoConfig(this.entries);

  static const empty = RepoConfig([]);

  /// The value git uses for [key], or null when it is set nowhere.
  ConfigEntry? effective(String key) => _last(key, null);

  /// The value [key] has in [scope] alone, or null when it is not set there.
  ConfigEntry? inScope(String key, ConfigScope scope) => _last(key, scope);

  ConfigEntry? _last(String key, ConfigScope? scope) {
    final k = key.toLowerCase();
    ConfigEntry? found;
    for (final e in entries) {
      if (e.key == k && (scope == null || e.scope == scope)) found = e;
    }
    return found;
  }
}

/// Parses `config --show-scope --show-origin -z --get-regexp` output: per
/// occurrence `scope\0origin\0key\nvalue\0`, or `key\0` for a bare key.
RepoConfig parseScopedConfig(String out) {
  final f = out.split('\x00');
  final entries = <ConfigEntry>[];
  // A complete record is three fields; the trailing NUL leaves one empty
  // piece, and anything shorter is a cut-off tail.
  for (var i = 0; i + 2 < f.length; i += 3) {
    final kv = f[i + 2];
    final nl = kv.indexOf('\n');
    final origin = f[i + 1];
    entries.add(
      ConfigEntry(
        scope: _scopeOf(f[i]),
        origin: origin.startsWith('file:') ? origin.substring(5) : null,
        key: nl < 0 ? kv : kv.substring(0, nl),
        value: nl < 0 ? null : kv.substring(nl + 1),
      ),
    );
  }
  return RepoConfig(entries);
}

/// How a key is edited.
enum ConfigKind { text, choice }

/// A key the Repository tab offers, spelled the way git documents it.
class RepoConfigKey {
  final String key;
  final ConfigKind kind;

  /// The values a choice key offers, besides leaving it unset.
  final List<String> choices;

  const RepoConfigKey(this.key, this.kind, [this.choices = const []]);
}

const _bool = ['true', 'false'];

/// The keys the Repository tab edits, in the order it shows them.
const kRepoConfigKeys = [
  RepoConfigKey('user.name', ConfigKind.text),
  RepoConfigKey('user.email', ConfigKind.text),
  RepoConfigKey('pull.rebase', ConfigKind.choice, ['false', 'true', 'merges']),
  RepoConfigKey('push.autoSetupRemote', ConfigKind.choice, _bool),
  RepoConfigKey('fetch.prune', ConfigKind.choice, _bool),
  RepoConfigKey('core.autocrlf', ConfigKind.choice, ['true', 'input', 'false']),
  RepoConfigKey('commit.gpgsign', ConfigKind.choice, _bool),
  RepoConfigKey('rerere.enabled', ConfigKind.choice, _bool),
];

RepoConfigKey repoConfigKey(String key) =>
    kRepoConfigKeys.firstWhere((k) => k.key == key);

/// `--get-regexp` pattern for every key in [kRepoConfigKeys]; git matches it
/// against lowercased names.
final kRepoConfigPattern =
    '^(${[for (final k in kRepoConfigKeys) RegExp.escape(k.key.toLowerCase())].join('|')})\$';

/// [raw] as one of [key]'s choices, read the way git reads it (`yes` is
/// `true`, a bare key is true), or null when it is none of them. Text keys
/// come back as they are.
String? normaliseConfigValue(RepoConfigKey key, String? raw) {
  if (key.kind == ConfigKind.text) return raw;
  final b = _gitBool(raw);
  final word = raw?.trim().toLowerCase();
  return switch (key.key) {
    'pull.rebase' when word == 'merges' || word == 'm' => 'merges',
    'core.autocrlf' when word == 'input' => 'input',
    _ => b == null ? null : '$b',
  };
}

/// A config boolean as git reads it, or null when git would reject it.
bool? _gitBool(String? v) {
  if (v == null) return true;
  final s = v.trim().toLowerCase();
  if (const {'true', 'yes', 'on'}.contains(s)) return true;
  if (const {'false', 'no', 'off', ''}.contains(s)) return false;
  final n = int.tryParse(s);
  return n == null ? null : n != 0;
}
