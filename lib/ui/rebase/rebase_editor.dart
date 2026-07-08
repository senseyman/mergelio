import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/rebase_plan.dart';

/// Interactive-rebase editor modal. Shows the commits (oldest first) with a
/// per-commit action, drag-to-reorder, inline reword, and a drop strike-through.
/// Returns the edited plan on Start, or null on cancel.
Future<List<RebaseStep>?> showRebaseEditor(
  BuildContext context, {
  required List<RebaseStep> steps,
}) {
  return showDialog<List<RebaseStep>>(
    context: context,
    builder: (ctx) => _RebaseEditor(initial: steps),
  );
}

class _RebaseEditor extends StatefulWidget {
  final List<RebaseStep> initial;
  const _RebaseEditor({required this.initial});

  @override
  State<_RebaseEditor> createState() => _RebaseEditorState();
}

class _RebaseEditorState extends State<_RebaseEditor> {
  late final List<RebaseStep> _steps = [...widget.initial];
  final _controllers = <String, TextEditingController>{};

  TextEditingController _controllerFor(RebaseStep s) => _controllers
      .putIfAbsent(s.sha, () => TextEditingController(text: s.message));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setAction(int i, RebaseAction a) => setState(
    () => _steps[i] = RebaseStep(_steps[i].sha, a, message: _steps[i].message),
  );

  void _setMessage(int i, String m) =>
      _steps[i] = RebaseStep(_steps[i].sha, _steps[i].action, message: m);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: t.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.rCard),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Text(
                'Interactive rebase',
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
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
            width: 96,
            child: DropdownButton<RebaseAction>(
              value: step.action,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              items: [
                for (final a in RebaseAction.values)
                  DropdownMenuItem(value: a, child: Text(a.name)),
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
