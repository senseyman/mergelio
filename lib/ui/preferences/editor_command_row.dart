import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/external_tools.dart';
import '../../l10n/gen/app_localizations.dart';

/// Preferences row choosing how "Open in editor" opens a file: the platform's
/// default app, a preset editor, or a command of the user's own.
class EditorCommandRow extends StatefulWidget {
  final String command;
  final ValueChanged<String> onChanged;
  const EditorCommandRow({
    super.key,
    required this.command,
    required this.onChanged,
  });

  @override
  State<EditorCommandRow> createState() => _EditorCommandRowState();
}

class _EditorCommandRowState extends State<EditorCommandRow> {
  late final _field = TextEditingController(text: widget.command);
  late final _focus = FocusNode()..addListener(_onFocus);

  /// Picked Custom while a preset is still what is saved: shows the field
  /// without writing anything until the user edits it.
  var _customPicked = false;

  /// What was last handed to [EditorCommandRow.onChanged]. Submitting also
  /// drops focus, and the parent has not rebuilt in between, so this stops
  /// the second save.
  late var _saved = widget.command;

  bool get _isPreset =>
      widget.command.isEmpty ||
      widget.command == kVsCodeEditor ||
      widget.command == kIdeaEditor;

  bool get _custom => _customPicked || !_isPreset;

  @override
  void didUpdateWidget(EditorCommandRow old) {
    super.didUpdateWidget(old);
    if (old.command != widget.command) {
      _saved = widget.command;
      if (!_focus.hasFocus) _field.text = widget.command;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _save();
  }

  void _save() {
    final text = _field.text.trim();
    if (text == _saved) return;
    _saved = text;
    widget.onChanged(text);
  }

  void _pick(String command) {
    setState(() => _customPicked = false);
    _field.text = command;
    if (command == _saved) return;
    _saved = command;
    widget.onChanged(command);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.prefsOpenFilesWith,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip(
                l.extEditorSystem,
                !_custom && widget.command.isEmpty,
                () => _pick(''),
              ),
              chip(
                l.extEditorVsCode,
                !_custom && widget.command == kVsCodeEditor,
                () => _pick(kVsCodeEditor),
              ),
              chip(
                l.extEditorIdea,
                !_custom && widget.command == kIdeaEditor,
                () => _pick(kIdeaEditor),
              ),
              chip(l.extEditorCustom, _custom, () {
                setState(() => _customPicked = true);
                _field.text = widget.command;
              }),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _field,
              focusNode: _focus,
              style: AppFonts.mns(size: 12.5, color: t.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                labelText: l.extEditorCommandLabel,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 4),
            Text(
              // The placeholders are command syntax, so they are not
              // translated.
              '${l.extEditorPlaceholders} {file} {line}',
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}
