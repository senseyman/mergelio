import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_controller.dart';
import 'dialogs.dart';
import '../../l10n/gen/app_localizations.dart';

/// Confirms a destructive action, honouring the "Confirm destructive actions"
/// preference: when the user has turned confirmations off, this returns true
/// immediately; otherwise it shows the standard confirm dialog.
Future<bool> confirmDestructive(
  WidgetRef ref,
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
}) async {
  final l = AppLocalizations.of(context);
  if (!ref.read(settingsProvider).confirmDestructive) return true;
  return showConfirmDialog(
    context,
    title: title,
    body: body,
    confirmLabel: confirmLabel ?? l.confirmAction,
  );
}
