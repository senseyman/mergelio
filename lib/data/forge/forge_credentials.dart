import '../../domain/git/git_service.dart';

/// A forge access token.
///
/// The wrapper exists for its [toString]: a token that reaches a log, a toast
/// or an exception message is a leak, and interpolation is how that happens.
/// Read [value] only where the token is about to be used.
class ForgeToken {
  final String value;
  const ForgeToken(this.value);

  @override
  String toString() => 'ForgeToken(hidden)';
}

/// The account name Mergelio stores its forge token under.
///
/// A host can hold several credentials, and the user very likely already has
/// one of their own for pushing. Writing and erasing under a name of our own
/// keeps the two apart: without it an erase matches every account on the host
/// and takes the user's push credential with it. GitHub accepts any username
/// alongside a token, and this is the name its own documentation uses.
const forgeTokenUsername = 'x-access-token';

/// Characters that cannot appear in a host name given to `git credential`.
/// The protocol is newline-delimited key=value lines terminated by a blank
/// one, so a host carrying a newline would add fields of its own choosing.
bool _usableHost(String host) {
  if (host.trim().isEmpty) return false;
  // Not redundant with the scan below: trim() also strips Unicode
  // whitespace such as U+00A0 (non-breaking space), U+2028 and U+3000,
  // none of which a code-unit scan for <= 0x20 can see. The credential
  // protocol only splits on '\n', so this isn't an injection vector — a
  // hostname just has no legitimate reason to carry exotic whitespace.
  if (host != host.trim()) return false;
  return !host.codeUnits.any((u) => u <= 0x20 || u == 0x7f);
}

/// Characters that cannot appear in any field written into a credential
/// body — username or token alike. Unlike [_usableHost], a legitimate
/// username or token may contain spaces or other printable characters; only
/// the line-structural characters and NUL must be refused, since either one
/// would let the value start a field of its own choosing on the next line.
bool _usableField(String value) {
  return !value.codeUnits.any((u) => u == 0 || u == 0x0a || u == 0x0d);
}

/// Environment for every `git credential` invocation in this file.
///
/// The UI's Connect row is the prompt: a helper that has nothing for a host
/// must fail silently so the caller can fall through to it, not open a
/// terminal prompt or an askpass dialog the user never asked for. Blanking
/// GIT_ASKPASS and SSH_ASKPASS matters as much as disabling the terminal
/// prompt — Dart's [Process.start] merges with the parent environment, so an
/// inherited askpass helper would otherwise still be live.
const _noPromptEnv = {
  'GIT_TERMINAL_PROMPT': '0',
  'GIT_ASKPASS': '',
  'SSH_ASKPASS': '',
};

/// [_noPromptEnv] already stops git from blocking on a terminal prompt — it
/// fails immediately instead of waiting, so this is not a guard against
/// that. What is left is a genuine operating-system keychain dialog, which
/// `git-credential-osxkeychain` raises and which is deliberately not
/// suppressed above; a user clicking through one can easily take longer than
/// ten seconds, and killing the process mid-dialog would report "no token"
/// for a credential the user actually has. Sixty seconds bounds a hung
/// helper, not someone reading a dialog.
const _credentialTimeout = Duration(seconds: 60);

/// The body `git credential fill` reads for [host], or null when [host] cannot
/// be expressed safely. Callers must treat null as "do not run git".
///
/// The protocol is always `https`, regardless of how [host]'s remote is
/// transported (ssh, git://, ...): the forge's API is reached over https no
/// matter how the repository itself is cloned, and the credential being
/// looked up here is the API's, deliberately independent of the remote's
/// transport.
String? credentialRequestFor(String host, String username) {
  if (!_usableHost(host)) return null;
  if (!_usableField(username)) return null;
  // The account has to be named. A host usually carries more than one — the
  // one this app stores for API reads, and whatever the person already had
  // for pushing — and a lookup that names none gets whichever the helper
  // happens to hold first. That is how a credential written under one
  // account gets read back as another.
  return 'protocol=https\nhost=$host\nusername=$username\n\n';
}

/// The key=value fields a `git credential` command wrote.
///
/// Lines without an `=` are skipped rather than guessed at; a value may itself
/// contain `=`, so only the first one separates.
Map<String, String> parseCredentialReply(String stdout) {
  final fields = <String, String>{};
  for (final raw in stdout.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    fields[line.substring(0, eq)] = line.substring(eq + 1);
  }
  return fields;
}

/// Reads and writes forge tokens through the credential helper the user has
/// already configured for git.
///
/// Mergelio stores no token of its own: whatever helper answers `git push` is
/// the one asked here, so a token the user revokes stays revoked and
/// uninstalling the app leaves no secret behind.
class ForgeCredentials {
  final GitService git;

  /// Repository whose configuration decides which helper answers. Null uses
  /// the global configuration.
  final String? repoPath;

  const ForgeCredentials(this.git, {this.repoPath});

  /// The token the helper holds for [host], or null when it has none, git
  /// fails, or [host] is unusable. Never throws: a missing credential is an
  /// ordinary answer that the caller turns into a connect prompt.
  ///
  /// This also swallows [GitUnavailableException], which carries advice for
  /// a missing or broken git install — that detail is lost here on purpose,
  /// in exchange for every caller being able to treat "no token" as the only
  /// failure mode instead of also handling a thrown exception.
  Future<ForgeToken?> fill(String host, String username) async {
    final request = credentialRequestFor(host, username);
    if (request == null) return null;
    final GitResult result;
    try {
      result = await git.run(
        const ['credential', 'fill'],
        repoPath: repoPath,
        stdin: request,
        environment: _noPromptEnv,
        timeout: _credentialTimeout,
      );
    } on GitException {
      return null;
    }
    if (!result.ok) return null;
    final password = parseCredentialReply(result.stdout)['password'];
    if (password == null || password.isEmpty) return null;
    // Symmetric with the checks every value leaving this file goes through:
    // a newline cannot survive parseCredentialReply's line splitting, but a
    // bare CR from a malicious or broken helper can, and this token is
    // headed for an HTTP Authorization header where that is header
    // injection.
    if (!_usableField(password)) return null;
    return ForgeToken(password);
  }

  /// Offers [token] to the helper so it survives the session. False means
  /// nothing was stored — either this file refused [host] or [username] or
  /// the token before git ever ran, git itself could not be run, or git ran
  /// and exited with failure. True means git accepted the credential; that
  /// still does not promise the helper chose to persist it, since a helper
  /// that silently declines to store still exits zero.
  Future<bool> approve(String host, String username, ForgeToken token) =>
      _write('approve', host, username, token);

  /// Asks the helper to forget the credential it holds for [username] on
  /// [host], so a rejected token is not handed back on the next attempt.
  ///
  /// [username] is not optional, and must not be empty: a credential helper
  /// matches an erase request on whatever fields the body carries, so a body
  /// with no username means "any account on this host" and erases the user's
  /// own push credential alongside this app's.
  ///
  /// False means nothing was forgotten — either this file refused [host],
  /// [username] or the token before git ever ran, git itself could not be
  /// run, or git ran and exited with failure. True means git accepted the
  /// request; it does not promise the helper had anything to forget.
  Future<bool> reject(String host, String username, ForgeToken token) {
    if (username.isEmpty) return Future.value(false);
    return _write('reject', host, username, token);
  }

  Future<bool> _write(
    String verb,
    String host,
    String username,
    ForgeToken token,
  ) async {
    // Every field lands in the same newline-delimited body, so every field
    // is checked the same way — a username or token that skipped this would
    // reopen the injection [_usableHost] exists to close for the host.
    if (!_usableHost(host)) return false;
    if (!_usableField(username)) return false;
    if (!_usableField(token.value)) return false;
    final buffer = StringBuffer('protocol=https\nhost=$host\n');
    if (username.isNotEmpty) buffer.write('username=$username\n');
    // git-credential-store (and osxkeychain) match an erase request on
    // whichever fields are present in the body; a password= field that is
    // present but empty still counts as a field to match, so it erases
    // nothing rather than the credential actually on disk. Omitting the
    // line entirely — not writing it empty — leaves host and username as
    // the only match criteria, which is what an erase-by-token-value-less
    // caller like reject means to ask for.
    if (token.value.isNotEmpty) buffer.write('password=${token.value}\n');
    buffer.write('\n');
    try {
      final result = await git.run(
        ['credential', verb],
        repoPath: repoPath,
        stdin: buffer.toString(),
        environment: _noPromptEnv,
        timeout: _credentialTimeout,
      );
      return result.ok;
    } on GitException {
      // A helper that refuses to record a credential leaves the token usable
      // for this session, which is the fallback the caller already handles.
      return false;
    }
  }
}
