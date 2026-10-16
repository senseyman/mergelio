import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import 'settings_controller.dart';

/// The strings for language [code], or — when no language is chosen — for
/// the first of the [system] languages the app ships, by the same rule
/// `MaterialApp` applies to the widgets. Anything unsupported reads English.
AppLocalizations appLocalizationsFor(String code, List<Locale> system) {
  bool supported(String c) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == c);
  if (code.isNotEmpty) {
    return lookupAppLocalizations(Locale(supported(code) ? code : 'en'));
  }
  for (final l in system) {
    if (supported(l.languageCode)) {
      return lookupAppLocalizations(Locale(l.languageCode));
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}

/// Strings for code that has no [BuildContext] to look them up from — the
/// toasts and progress labels repo actions raise.
///
/// English until the app installs [appL10nOverride], so a container built
/// without it (most tests) still gets readable messages.
final appL10nProvider = Provider<AppLocalizations>(
  (ref) => lookupAppLocalizations(const Locale('en')),
);

/// Points [appL10nProvider] at the language the user picked in Preferences,
/// following it as it changes.
final appL10nOverride = appL10nProvider.overrideWith(
  (ref) => appLocalizationsFor(
    ref.watch(settingsProvider.select((s) => s.localeCode)),
    PlatformDispatcher.instance.locales,
  ),
);
