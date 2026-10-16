import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/ssh_keys.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/preferences/ssh_key_error_text.dart';

void main() {
  final uk = lookupAppLocalizations(const Locale('uk'));

  test('each refusal reads in the chosen language', () {
    expect(
      sshKeyErrorText(
        uk,
        const SshKeyException(SshKeyError.invalidName, 'a/b'),
      ),
      uk.pfSshKeyInvalidName('a/b'),
    );
    expect(
      sshKeyErrorText(uk, const SshKeyException(SshKeyError.exists, 'k')),
      uk.pfSshKeyExists('k'),
    );
  });

  test("ssh-keygen's own output is passed through after the heading", () {
    expect(
      sshKeyErrorText(
        uk,
        const SshKeyException(
          SshKeyError.keygenFailed,
          'k',
          detail: 'no space left',
        ),
      ),
      uk.pfSshKeygenFailed('no space left'),
    );
  });

  test('anything else keeps its own text', () {
    expect(sshKeyErrorText(uk, StateError('x')), 'Bad state: x');
  });
}
