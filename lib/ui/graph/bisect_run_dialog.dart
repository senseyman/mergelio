import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_writer.dart';
import '../../l10n/gen/app_localizations.dart';
import '../common/dialogs.dart';

/// Prompts for a command to hand `git bisect run`, showing the exact
/// argv it will execute (shell wrapper included) before it fires.
///
/// Nothing here is remembered between opens: the field always starts
/// empty, since replaying a command typed for an earlier hunt is more
/// likely to be wrong than typing it again.
///
/// Returns the trimmed command, or null when cancelled or the barrier is
/// dismissed without a choice.
Future<String?> showBisectRunDialog(BuildContext context) {
  final l = AppLocalizations.of(context);
  return showAppModal<String>(
    context: context,
    title: l.bisectRunTitle,
    icon: Icons.terminal_outlined,
    width: 480,
    body: const _BisectRunBody(),
  );
}

class _BisectRunBody extends StatefulWidget {
  const _BisectRunBody();

  @override
  State<_BisectRunBody> createState() => _BisectRunBodyState();
}

class _BisectRunBodyState extends State<_BisectRunBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final command = _controller.text.trim();
    if (command.isEmpty) return;
    Navigator.of(context).pop(command);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final command = _controller.text.trim();
    // The real argv, shell wrapper included, so what is shown is exactly
    // what will run — no gap between the preview and the execution.
    final preview = command.isEmpty ? '' : bisectRunArgs(command).join(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          style: TextStyle(color: t.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: l.bisectRunHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(
          l.bisectRunWillExecute,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.bgApp,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.rCard),
          ),
          child: SelectableText(
            preview,
            style: AppFonts.mns(size: 11.5, color: t.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l.bisectRunTreeWarning,
          style: TextStyle(color: t.textMuted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: command.isEmpty ? null : _submit,
              child: Text(l.bisectRunStart),
            ),
          ],
        ),
      ],
    );
  }
}
