import '../../domain/ssh_keys.dart';
import '../../l10n/gen/app_localizations.dart';

/// The toast description for a failed key generation: an [SshKeyException]
/// in the chosen language, anything else as it describes itself.
String sshKeyErrorText(AppLocalizations l, Object e) => switch (e) {
  SshKeyException(kind: SshKeyError.invalidName) => l.pfSshKeyInvalidName(
    e.name,
  ),
  SshKeyException(kind: SshKeyError.exists) => l.pfSshKeyExists(e.name),
  SshKeyException(kind: SshKeyError.keygenFailed) => l.pfSshKeygenFailed(
    e.detail,
  ),
  _ => '$e',
};
