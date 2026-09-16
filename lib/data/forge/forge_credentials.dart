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

/// Characters that cannot appear in a host name given to `git credential`.
/// The protocol is newline-delimited key=value lines terminated by a blank
/// one, so a host carrying a newline would add fields of its own choosing.
bool _usableHost(String host) {
  if (host.trim().isEmpty) return false;
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

/// The body `git credential fill` reads for [host], or null when [host] cannot
/// be expressed safely. Callers must treat null as "do not run git".
String? credentialRequestFor(String host) {
  if (!_usableHost(host)) return null;
  return 'protocol=https\nhost=$host\n\n';
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
  Future<ForgeToken?> fill(String host) async {
    final request = credentialRequestFor(host);
    if (request == null) return null;
    final GitResult result;
    try {
      result = await git.run(
        const ['credential', 'fill'],
        repoPath: repoPath,
        stdin: request,
      );
    } on GitException {
      return null;
    }
    if (!result.ok) return null;
    final password = parseCredentialReply(result.stdout)['password'];
    if (password == null || password.isEmpty) return null;
    return ForgeToken(password);
  }

  /// Offers [token] to the helper so it survives the session. A helper that
  /// declines to store anything is not an error.
  Future<void> approve(String host, String username, ForgeToken token) =>
      _write('approve', host, username, token);

  /// Asks the helper to forget its credential for [host], so a rejected token
  /// is not handed back on the next attempt.
  Future<void> reject(String host, ForgeToken token) =>
      _write('reject', host, '', token);

  Future<void> _write(
    String verb,
    String host,
    String username,
    ForgeToken token,
  ) async {
    // Every field lands in the same newline-delimited body, so every field
    // is checked the same way — a username or token that skipped this would
    // reopen the injection [_usableHost] exists to close for the host.
    if (!_usableHost(host)) return;
    if (!_usableField(username)) return;
    if (!_usableField(token.value)) return;
    final buffer = StringBuffer('protocol=https\nhost=$host\n');
    if (username.isNotEmpty) buffer.write('username=$username\n');
    buffer.write('password=${token.value}\n\n');
    try {
      await git.run(
        ['credential', verb],
        repoPath: repoPath,
        stdin: buffer.toString(),
      );
    } on GitException {
      // A helper that refuses to record a credential leaves the token usable
      // for this session, which is the fallback the caller already handles.
    }
  }
}
