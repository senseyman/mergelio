import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/git_service.dart';
import '../../l10n/gen/app_localizations.dart';

/// Text and state widgets shared by the maintenance panel and the branch
/// clean-up list, so the two read as one family.
TextStyle mntBodyStyle(AppTokens t, {Color? color}) =>
    TextStyle(color: color ?? t.textPrimary, fontSize: 13);

TextStyle mntFaintStyle(AppTokens t) =>
    TextStyle(color: t.textFaint, fontSize: 12);

Widget mntLoading() => const Padding(
  padding: EdgeInsets.symmetric(vertical: 4),
  child: LinearProgressIndicator(minHeight: 2),
);

/// What git said, when it said anything; otherwise the short reason. Never
/// the exception's own rendering, which is a developer's dump.
String _reason(Object error) {
  if (error is GitException) {
    final err = error.result?.err ?? '';
    return err.isNotEmpty ? err : error.message;
  }
  return '$error';
}

Widget mntFailed(BuildContext context, Object error) => Text(
  AppLocalizations.of(context).mntReadFailed(_reason(error)),
  style: mntBodyStyle(context.tokens, color: context.tokens.danger),
);
