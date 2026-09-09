import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/askpass.dart';
import '../../l10n/gen/app_localizations.dart';

/// The window git and ssh get in place of the terminal they cannot reach: the
/// prompt they asked with, and a way to answer it.
///
/// The answer is handed straight back to the process that asked — this widget
/// keeps no copy and stores nothing.
class AskpassPrompt extends StatefulWidget {
  final String prompt;
  final void Function(String answer) onAnswer;
  final VoidCallback onCancel;

  const AskpassPrompt({
    super.key,
    required this.prompt,
    required this.onAnswer,
    required this.onCancel,
  });

  @override
  State<AskpassPrompt> createState() => _AskpassPromptState();
}

class _AskpassPromptState extends State<AskpassPrompt> {
  final _controller = TextEditingController();
  late final AskpassKind _kind = askpassKindOf(widget.prompt);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => widget.onAnswer(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final confirm = _kind == AskpassKind.confirm;
    final prompt = widget.prompt.trim();
    return CallbackShortcuts(
      // Escape declines, the same as the Cancel button: the command that asked
      // gets a refusal rather than an empty answer it would try to use.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Material(
        color: t.bgApp,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: t.textPrimary),
                  const SizedBox(width: 8),
                  Text(
                    l.askpassTitle,
                    style: AppFonts.disp(size: 16, color: t.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Verbatim: the host, key file or URL git named is the only way to
              // tell which of several remotes is asking.
              Text(
                prompt.isEmpty ? l.askpassFallback : prompt,
                style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (!confirm)
                TextField(
                  controller: _controller,
                  autofocus: true,
                  obscureText: _kind == AskpassKind.secret,
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(color: t.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: confirm
                    ? [
                        // ssh wants the word, not a dead helper: answering "no"
                        // ends the connection cleanly with a reason.
                        TextButton(
                          onPressed: () => widget.onAnswer('no'),
                          child: Text(l.askpassNo),
                        ),
                        FilledButton(
                          // Nothing else takes focus in this mode, and the
                          // Escape binding above needs something that has it.
                          autofocus: true,
                          onPressed: () => widget.onAnswer('yes'),
                          child: Text(l.askpassYes),
                        ),
                      ]
                    : [
                        TextButton(
                          onPressed: widget.onCancel,
                          child: Text(l.cancel),
                        ),
                        FilledButton(
                          onPressed: _submit,
                          child: Text(l.askpassSubmit),
                        ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
