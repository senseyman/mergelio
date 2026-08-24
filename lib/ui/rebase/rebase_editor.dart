import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/rebase_plan.dart';

/// Interactive-rebase editor modal. Opens on a single whole-branch choice —
/// move the commits as they are, or fold them into one — and only unfolds the
/// per-commit table (action, drag-to-reorder, inline reword) when the user asks
/// to customize. Every choice carries its own plain-language description, so
/// nobody has to already know what `fixup` does. Returns the edited plan on
/// Start, or null on cancel.
Future<List<RebaseStep>?> showRebaseEditor(
  BuildContext context, {
  required List<RebaseStep> steps,
  String? onto,
}) {
  return showDialog<List<RebaseStep>>(
    context: context,
    builder: (ctx) => _RebaseEditor(initial: steps, onto: onto),
  );
}

/// What each git action does, in the words of someone who has not read the
/// rebase man page.
String rebaseActionSummary(RebaseAction a) => switch (a) {
  RebaseAction.pick => 'keep this commit as it is',
  RebaseAction.reword => 'keep this commit, change its message',
  RebaseAction.squash => 'merge into the commit above, keep both messages',
  RebaseAction.fixup => 'merge into the commit above, drop its message',
  RebaseAction.drop => 'remove this commit entirely',
};

String _presetTitle(RebasePreset p) => switch (p) {
  RebasePreset.asIs => 'Move commits as-is',
  RebasePreset.squashAll => 'Squash into one commit',
  RebasePreset.squashKeepFirst => 'Squash, keep first message',
};

String _presetSummary(RebasePreset p, int count) => switch (p) {
  RebasePreset.asIs =>
    'Replay all $count commits on the new base. History keeps its shape.',
  RebasePreset.squashAll =>
    'Combine all $count into one commit; all messages are kept, '
        'one after another.',
  RebasePreset.squashKeepFirst =>
    'Combine all $count into one commit; only the first message is kept.',
};

class _RebaseEditor extends StatefulWidget {
  final List<RebaseStep> initial;
  final String? onto;
  const _RebaseEditor({required this.initial, this.onto});

  @override
  State<_RebaseEditor> createState() => _RebaseEditorState();
}

class _RebaseEditorState extends State<_RebaseEditor> {
  late List<RebaseStep> _steps = applyPreset(widget.initial, RebasePreset.asIs);
  final _controllers = <String, TextEditingController>{};

  /// Null once the user has taken the plan into their own hands; a preset
  /// otherwise. Switching to customize keeps whatever the preset produced, so
  /// the per-commit table extends the choice instead of resetting it.
  RebasePreset? _preset = RebasePreset.asIs;

  bool get _custom => _preset == null;

  /// Squashing needs something to squash into.
  bool get _canSquash => _steps.length > 1;

  TextEditingController _controllerFor(RebaseStep s) => _controllers
      .putIfAbsent(s.sha, () => TextEditingController(text: s.message));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _choosePreset(RebasePreset? p) => setState(() {
    _preset = p;
    if (p != null) _steps = applyPreset(_steps, p);
  });

  void _setAction(int i, RebaseAction a) => setState(
    () => _steps[i] = RebaseStep(
      _steps[i].sha,
      a,
      message: _steps[i].message,
      sign: _steps[i].sign,
    ),
  );

  void _setMessage(int i, String m) => _steps[i] = RebaseStep(
    _steps[i].sha,
    _steps[i].action,
    message: m,
    sign: _steps[i].sign,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final count = _steps.length;
    final onto = widget.onto;
    return Dialog(
      backgroundColor: t.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.rCard),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Interactive rebase',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$count ${count == 1 ? 'commit' : 'commits'}'
                    '${onto == null ? '' : ' onto $onto'}',
                    style: TextStyle(color: t.textFaint, fontSize: 12),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: t.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RadioGroup<RebasePreset>(
                      groupValue: _preset,
                      onChanged: _choosePreset,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final p in RebasePreset.values)
                            _PresetTile(
                              preset: p,
                              count: count,
                              enabled: p == RebasePreset.asIs || _canSquash,
                            ),
                        ],
                      ),
                    ),
                    _CustomizeTile(
                      selected: _custom,
                      onSelected: () => _choosePreset(null),
                    ),
                    if (_custom) ...[
                      Divider(height: 1, color: t.border),
                      _stepList(),
                      Divider(height: 1, color: t.border),
                      _legend(t),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_steps),
                    child: const Text('Start rebase'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepList() => ReorderableListView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(vertical: 8),
    // ignore: deprecated_member_use
    onReorder: (oldI, newI) => setState(() {
      if (newI > oldI) newI--;
      _steps.insert(newI, _steps.removeAt(oldI));
    }),
    children: [
      for (var i = 0; i < _steps.length; i++)
        _StepRow(
          key: ValueKey(_steps[i].sha),
          index: i,
          step: _steps[i],
          controller: _controllerFor(_steps[i]),
          onAction: (a) => _setAction(i, a),
          onMessage: (m) => _setMessage(i, m),
        ),
    ],
  );

  Widget _legend(AppTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Text(
      [
        for (final a in RebaseAction.values)
          '${a.name} — ${rebaseActionSummary(a)}',
      ].join('  ·  '),
      style: TextStyle(color: t.textFaint, fontSize: 11.5, height: 1.5),
    ),
  );
}

class _PresetTile extends StatelessWidget {
  final RebasePreset preset;
  final int count;
  final bool enabled;
  const _PresetTile({
    required this.preset,
    required this.count,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return RadioListTile<RebasePreset>(
      value: preset,
      enabled: enabled,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        _presetTitle(preset),
        style: TextStyle(
          color: enabled ? t.textPrimary : t.textFaint,
          fontSize: 13.5,
        ),
      ),
      subtitle: Text(
        enabled ? _presetSummary(preset, count) : 'Needs at least 2 commits.',
        style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.35),
      ),
    );
  }
}

/// Customize is not a preset — it is the absence of one — so it gets its own
/// tile rather than a fourth radio value that `applyPreset` would have to know
/// how to ignore.
class _CustomizeTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onSelected;
  const _CustomizeTile({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListTile(
      dense: true,
      onTap: onSelected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: selected ? t.accent : t.textFaint,
      ),
      title: Text(
        'Customize per commit',
        style: TextStyle(color: t.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        'Pick an action for each commit, or drag to reorder them.',
        style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final RebaseStep step;
  final TextEditingController controller;
  final ValueChanged<RebaseAction> onAction;
  final ValueChanged<String> onMessage;
  const _StepRow({
    super.key,
    required this.index,
    required this.step,
    required this.controller,
    required this.onAction,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dropped = step.action == RebaseAction.drop;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_indicator, size: 16, color: t.textFaint),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: DropdownButton<RebaseAction>(
              value: step.action,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              // The closed button shows only the action name; the open menu is
              // where there is room to say what it does.
              selectedItemBuilder: (_) => [
                for (final a in RebaseAction.values)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      a.name,
                      style: TextStyle(color: t.textPrimary, fontSize: 12),
                    ),
                  ),
              ],
              items: [
                for (final a in RebaseAction.values)
                  DropdownMenuItem(
                    value: a,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: a.name),
                          TextSpan(
                            text: ' — ${rebaseActionSummary(a)}',
                            style: TextStyle(color: t.textFaint),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textPrimary, fontSize: 12),
                    ),
                  ),
              ],
              onChanged: (a) => a == null ? null : onAction(a),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: step.action == RebaseAction.reword
                ? TextField(
                    controller: controller,
                    onChanged: onMessage,
                    style: TextStyle(color: t.textPrimary, fontSize: 12.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  )
                : Text(
                    step.message,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dropped ? t.textFaint : t.textMuted,
                      fontSize: 12.5,
                      decoration: dropped ? TextDecoration.lineThrough : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
