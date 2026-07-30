import 'dart:io';

import 'package:path/path.dart' as p;

/// One SSH public key found on the machine.
class SshKey {
  final String name; // file stem, e.g. id_ed25519
  final String path; // absolute path to the .pub file
  final String publicKey; // full public-key line
  const SshKey({
    required this.name,
    required this.path,
    required this.publicKey,
  });
}

/// Reads and creates SSH keys in the user's `~/.ssh`. Private keys are never
/// read or held — only `.pub` files are listed, and generation shells out to
/// the system `ssh-keygen`, so key material stays with the OS tooling.
class SshKeys {
  final String sshDir;
  SshKeys({String? dir})
    : sshDir =
          dir ??
          p.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '.',
            '.ssh',
          );

  /// All public keys in the SSH directory, sorted by name.
  Future<List<SshKey>> list() async {
    final d = Directory(sshDir);
    if (!await d.exists()) return const [];
    final keys = <SshKey>[];
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.pub')) continue;
      try {
        final content = (await f.readAsString()).trim();
        keys.add(
          SshKey(
            name: p.basenameWithoutExtension(f.path),
            path: f.path,
            publicKey: content,
          ),
        );
      } on Object {
        // Unreadable file — skip rather than fail the whole listing.
      }
    }
    keys.sort((a, b) => a.name.compareTo(b.name));
    return keys;
  }

  /// Generates a new ed25519 key pair named [name] via the system
  /// `ssh-keygen`. The key is created without a passphrase (the standard for
  /// tooling-managed keys); the UI advises `ssh-keygen -p` to add one.
  /// Returns the new public key, or throws with ssh-keygen's stderr.
  Future<SshKey> generate(String name, {required String comment}) async {
    // The name is a file stem inside ~/.ssh — never a path. Reject separators
    // and dot-segments so a crafted name cannot write outside the directory.
    if (name.isEmpty ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name) ||
        name.contains('..')) {
      throw StateError('Invalid key name: $name');
    }
    final keyPath = p.join(sshDir, name);
    if (File(keyPath).existsSync() || File('$keyPath.pub').existsSync()) {
      throw StateError('A key named $name already exists');
    }
    await Directory(sshDir).create(recursive: true);
    // Strip control characters and leading dashes from the comment to prevent
    // ssh-keygen from misinterpreting it as a command-line flag.
    final safeComment = comment
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
        .replaceFirst(RegExp(r'^-+'), '');
    final r = await Process.run('ssh-keygen', [
      '-t',
      'ed25519',
      '-f',
      keyPath,
      '-N',
      '',
      '-C',
      safeComment,
    ]);
    if (r.exitCode != 0) {
      throw StateError('ssh-keygen failed: ${r.stderr}');
    }
    final publicKey = (await File('$keyPath.pub').readAsString()).trim();
    return SshKey(name: name, path: '$keyPath.pub', publicKey: publicKey);
  }
}
