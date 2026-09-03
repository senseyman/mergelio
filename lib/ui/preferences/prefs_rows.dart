import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// A labelled switch, shared by the Preferences tabs so a setting looks the
/// same wherever it is offered.
class SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow(this.label, this.value, this.onChanged, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label, style: TextStyle(color: t.textPrimary, fontSize: 13)),
      value: value,
      activeThumbColor: t.accent,
      onChanged: onChanged,
    );
  }
}
