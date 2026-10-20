/// Handing a file to a program outside Mergelio: the user's editor, or the
/// diff and merge tools git is configured with. Everything here is string
/// work, so it is the same on every platform and can be checked without
/// spawning anything.
library;

/// VS Code: open at a line, reusing the window it already has.
const kVsCodeEditor = 'code -g {file}:{line}';

/// IntelliJ IDEA (and, renamed, the other JetBrains IDEs).
const kIdeaEditor = 'idea --line {line} {file}';

/// How many diff tools may be open at once. Each holds a git process — and
/// one of the app's shared git slots — for as long as its window is open.
const kMaxOpenDiffTools = 4;

/// How long a diff or merge tool may stay open. It is a window the user works
/// in, so the limit only exists to reclaim a git that will never return.
const kExternalToolTimeout = Duration(hours: 12);

/// Splits [command] into words the way a POSIX shell would, without running
/// one: whitespace separates, `'…'` and `"…"` keep spaces, a backslash escapes
/// the next character outside single quotes. Nothing is expanded. Throws a
/// [FormatException] for a quote left open.
List<String> splitCommand(String command) {
  final words = <String>[];
  final word = StringBuffer();
  // A word exists once anything — even an empty pair of quotes — started it.
  var inWord = false;
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (quote == "'") {
      if (ch == "'") {
        quote = null;
      } else {
        word.write(ch);
      }
      continue;
    }
    if (ch == r'\' && i + 1 < command.length) {
      final next = command[i + 1];
      // Inside double quotes only the characters a shell treats specially
      // there are escaped; any other backslash is kept as written.
      if (quote == '"' && next != '"' && next != r'\') {
        word.write(ch);
      } else {
        word.write(next);
        i++;
      }
      inWord = true;
      continue;
    }
    if (quote == '"') {
      if (ch == '"') {
        quote = null;
      } else {
        word.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) words.add(word.toString());
      word.clear();
      inWord = false;
    } else {
      word.write(ch);
      inWord = true;
    }
  }
  if (quote != null) {
    throw FormatException('Unclosed $quote in the command', command);
  }
  if (inWord) words.add(word.toString());
  return words;
}

/// The executable and arguments that open [file] for [command]. An empty
/// command means the platform's default app for the file, which has no way to
/// be told a line.
///
/// `{file}` and `{line}` are replaced wherever they appear in an argument;
/// a command that never says `{file}` gets the file appended. Throws a
/// [FormatException] for a command that does not split, or has no program.
(String, List<String>) editorInvocation(
  String command,
  String file, {
  int line = 1,
  required String os,
}) {
  if (command.trim().isEmpty) {
    final opener = switch (os) {
      'macos' => 'open',
      'windows' => 'explorer',
      _ => 'xdg-open',
    };
    return (opener, [file]);
  }
  final words = splitCommand(command);
  if (words.isEmpty || words.first.isEmpty) {
    throw FormatException('No program in the command', command);
  }
  var named = false;
  final args = [
    for (final w in words.skip(1))
      w.replaceAllMapped(RegExp(r'\{(file|line)\}'), (m) {
        if (m[1] == 'line') return '$line';
        named = true;
        return file;
      }),
  ];
  if (!named) args.add(file);
  return (words.first, args);
}

/// Where editors and diff tools are commonly installed but a Finder, Dock or
/// desktop launch does not look: the session's PATH is only the system's.
List<String> toolSearchDirs({required String os, required String home}) =>
    switch (os) {
      'macos' => [
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '$home/.local/bin',
        '$home/bin',
        // The `code` command VS Code ships, for anyone who never ran its
        // "Install 'code' command in PATH".
        '/Applications/Visual Studio Code.app/Contents/Resources/app/bin',
        '$home/Applications/Visual Studio Code.app/Contents/Resources/app/bin',
        '$home/Library/Application Support/JetBrains/Toolbox/scripts',
      ],
      'linux' => [
        '$home/.local/bin',
        '$home/bin',
        '/usr/local/bin',
        '/snap/bin',
        '$home/.local/share/JetBrains/Toolbox/scripts',
      ],
      _ => const [],
    };

/// [current] with [toolSearchDirs] appended, skipping any already on it.
/// Appended, not prepended, so whatever the system resolves keeps winning.
String toolSearchPath(
  String? current, {
  required String os,
  required String home,
}) {
  final sep = os == 'windows' ? ';' : ':';
  final dirs = (current ?? '').split(sep).where((d) => d.isNotEmpty).toList();
  String norm(String d) =>
      d.length > 1 && d.endsWith('/') ? d.substring(0, d.length - 1) : d;
  final seen = {for (final d in dirs) norm(d)};
  for (final d in toolSearchDirs(os: os, home: home)) {
    if (seen.add(d)) dirs.add(d);
  }
  return dirs.join(sep);
}

/// The file [name] runs, looked up on [path] the way the OS would, or null
/// when there is none. A name with a directory in it is taken as given, a
/// leading `~/` standing for [home] as it would in a shell. On Windows a name
/// without an extension is tried with each executable one.
String? resolveExecutable(
  String name, {
  required String? path,
  required String os,
  required bool Function(String path) exists,
  String? home,
}) {
  if (home != null && name.startsWith('~/')) {
    name = '$home${name.substring(1)}';
  }
  final windows = os == 'windows';
  final hasDir = name.contains('/') || (windows && name.contains(r'\'));
  final hasExt = name.contains('.');
  final names = windows && !hasExt
      ? [
          for (final e in const ['.exe', '.cmd', '.bat', '.com']) '$name$e',
        ]
      : [name];
  if (hasDir) {
    for (final n in names) {
      if (exists(n)) return n;
    }
    return null;
  }
  final sep = windows ? ';' : ':';
  final slash = windows ? r'\' : '/';
  for (final dir in (path ?? '').split(sep)) {
    if (dir.isEmpty) continue;
    final base = dir.endsWith(slash) ? dir : '$dir$slash';
    for (final n in names) {
      if (exists('$base$n')) return '$base$n';
    }
  }
  return null;
}

/// The diff and merge tool settings git would use, as read by
/// `config -z --get-regexp`.
class ExternalToolConfig {
  final Map<String, String> values;
  const ExternalToolConfig(this.values);

  static const empty = ExternalToolConfig({});

  String? value(String key) => values[key];
}

/// `config --get-regexp` pattern for every key [pickExternalTool] reads; git
/// matches it against lowercased names.
const kExternalToolConfigPattern =
    r'^(diff|merge)\.(gui)?tool$|^(diff|merge)tool\..*\.cmd$';

/// Parses `config -z --get-regexp` output: per occurrence `key\nvalue\0`, or
/// `key\0` for a key with no value. Later occurrences override earlier ones,
/// as they do for git.
ExternalToolConfig parseToolConfig(String out) {
  final values = <String, String>{};
  for (final record in out.split('\x00')) {
    if (record.isEmpty) continue;
    final nl = record.indexOf('\n');
    if (nl < 0) {
      values[record] = '';
    } else {
      values[record.substring(0, nl)] = record.substring(nl + 1);
    }
  }
  return ExternalToolConfig(values);
}

enum ToolKind { diff, merge }

/// Whether git has a tool Mergelio can hand a file to.
sealed class ToolChoice {
  const ToolChoice();
}

/// Run git's tool command, with `--gui` when the tool came from a `guitool`
/// key so git picks that one too.
class ToolReady extends ToolChoice {
  final String name;
  final bool gui;
  const ToolReady(this.name, {required this.gui});

  @override
  bool operator ==(Object other) =>
      other is ToolReady && other.name == name && other.gui == gui;

  @override
  int get hashCode => Object.hash(name, gui);

  @override
  String toString() => 'ToolReady($name, gui: $gui)';
}

/// No tool is configured. git would fall back to a guess of its own, which on
/// most systems is a terminal tool with no terminal to draw in.
class ToolMissing extends ToolChoice {
  const ToolMissing();

  @override
  bool operator ==(Object other) => other is ToolMissing;

  @override
  int get hashCode => 0;
}

/// The configured tool is one of git's built-in terminal programs; started
/// from an app it has no terminal, so it either fails or hangs unseen.
class ToolNeedsTerminal extends ToolChoice {
  final String name;
  const ToolNeedsTerminal(this.name);

  @override
  bool operator ==(Object other) =>
      other is ToolNeedsTerminal && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// git's built-in tools that draw in the terminal they were started from.
const kTerminalTools = {
  'vimdiff',
  'vimdiff1',
  'vimdiff2',
  'vimdiff3',
  'nvimdiff',
  'nvimdiff1',
  'nvimdiff2',
  'nvimdiff3',
  'emerge',
};

/// The tool git will run for [kind], mirroring git's own lookup: the
/// `guitool` key first (which needs `--gui` to take effect), then `tool`; a
/// diff falls back to the merge tool, a merge never to the diff tool.
ToolChoice pickExternalTool(ExternalToolConfig config, ToolKind kind) {
  String? set(String key) {
    final v = config.value(key)?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  final section = kind == ToolKind.diff ? 'diff' : 'merge';
  final gui = set('$section.guitool');
  final name =
      gui ??
      set('$section.tool') ??
      (kind == ToolKind.diff ? set('merge.tool') : null);
  if (name == null) return const ToolMissing();
  // A cmd of the user's own under a builtin's name replaces the builtin.
  // difftool also takes the mergetool one; mergetool never the difftool one.
  final custom =
      set('${section}tool.$name.cmd') ??
      (kind == ToolKind.diff ? set('mergetool.$name.cmd') : null);
  if (kTerminalTools.contains(name) && custom == null) {
    return ToolNeedsTerminal(name);
  }
  return ToolReady(name, gui: gui != null);
}

/// `git difftool` for one file. With [to] unset it is a working-tree change —
/// [staged] picks the index side — and with it set, [from] → [to]. [origPath]
/// is where a renamed file came from, so both of its names are compared.
List<String> difftoolArgs({
  required String path,
  String? origPath,
  String? from,
  String? to,
  bool staged = false,
  bool gui = false,
}) => [
  'difftool',
  '--no-prompt',
  if (gui) '--gui',
  if (to == null && staged) '--cached',
  if (to != null) ...['-M', ?from, to],
  '--',
  if (origPath != null && origPath != path) origPath,
  path,
];

/// Which of [names] — the entries of [relPath]'s directory — are the copies
/// `git mergetool` makes of it while a tool is open: `<stem>_BASE_<pid><ext>`
/// and the like, split at the last dot. git removes them when the tool
/// closes, but not when git itself is killed first.
List<String> mergetoolLeftovers(String relPath, Iterable<String> names) {
  final base = relPath.substring(relPath.lastIndexOf('/') + 1);
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot) : '';
  final copy = RegExp(
    '^${RegExp.escape(stem)}_(BACKUP|BASE|LOCAL|REMOTE)_[0-9]+'
    '${RegExp.escape(ext)}\$',
  );
  return [
    for (final n in names)
      if (copy.hasMatch(n)) n,
  ];
}

/// `git mergetool` for one conflicted file. git stages it when the tool
/// reports success, and does nothing else.
List<String> mergetoolArgs(String path, {bool gui = false}) => [
  'mergetool',
  '--no-prompt',
  if (gui) '--gui',
  '--',
  path,
];
