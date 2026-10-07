import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/rebase_plan.dart';
import '../../l10n/gen/app_localizations.dart';

/// Interactive-rebase editor modal. Opens on a single whole-branch choice —
/// move the commits as they are, or fold them into one — and only unfolds the
/// per-commit table (action, drag-to-reorder, inline reword, exec and break
/// steps) when the user asks to customize. Every choice carries its own
/// plain-language description, so nobody has to already know what `fixup`
/// does. [stackedBranches] are the branches sitting on these commits, offered
/// to move along. Returns the edited plan on Start, or null on cancel.
Future<RebasePlan?> showRebaseEditor(
  BuildContext context, {
  required List<RebaseStep> steps,
  String? onto,
  List<String> stackedBranches = const [],
}) {
  return showDialog<RebasePlan>(
    context: context,
    builder: (ctx) => _RebaseEditor(
      initial: steps,
      onto: onto,
      stackedBranches: stackedBranches,
    ),
  );
}

/// What each git action does, in the words of someone who has not read the
/// rebase man page.
String rebaseActionSummary(AppLocalizations l, RebaseAction a) => switch (a) {
  RebaseAction.pick => l.rbPick,
  RebaseAction.reword => l.rbReword,
  RebaseAction.squash => l.rbSquash,
  RebaseAction.fixup => l.rbFixup,
  RebaseAction.drop => l.rbDrop,
  RebaseAction.exec => l.rbExec,
  RebaseAction.breakpoint => l.rbBreak,
};

String _presetTitle(AppLocalizations l, RebasePreset p) => switch (p) {
  RebasePreset.asIs => l.rbPresetAsIs,
  RebasePreset.squashAll => l.rbPresetSquashAll,
  RebasePreset.squashKeepFirst => l.rbPresetSquashKeepFirst,
};

String _presetSummary(AppLocalizations l, RebasePreset p, int count) =>
    switch (p) {
      RebasePreset.asIs => l.rbSummaryAsIs(count),
      RebasePreset.squashAll => l.rbSummarySquashAll(count),
      RebasePreset.squashKeepFirst => l.rbSummarySquashKeepFirst(count),
    };

/// The word git uses for [a] in a todo — `break` is a Dart keyword, so the enum
/// value cannot carry it.
String _verb(RebaseAction a) => a == RebaseAction.breakpoint ? 'break' : a.name;

class _RebaseEditor extends StatefulWidget {
  final List<RebaseStep> initial;
  final String? onto;
  final List<String> stackedBranches;
  const _RebaseEditor({
    required this.initial,
    this.onto,
    this.stackedBranches = const [],
  });

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

  /// How many commits ask to be folded into another; the autosquash switch
  /// is only offered when there is something for it to do.
  late final int _autosquashable = autosquash(widget.initial).pairs.length;

  /// Folded commit id → the id of the commit it folds into, while autosquash
  /// is on; empty while it is off.
  var _paired = <String, String>{};

  bool get _autosquash => _paired.isNotEmpty;

  var _updateRefs = false;

  /// Names the exec and break steps this editor adds; they have no sha.
  var _added = 0;

  TextEditingController _controllerFor(RebaseStep s) =>
      _controllers.putIfAbsent(
        s.id,
        () => TextEditingController(
          text: s.action == RebaseAction.exec ? s.command : s.message,
        ),
      );

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _choosePreset(RebasePreset? p) => setState(() {
    _preset = p;
    if (p == null) return;
    // A preset speaks for every commit; the pairing autosquash drew would be
    // overwritten half-way, so it is taken back whole first.
    if (_autosquash) _unfold();
    _steps = applyPreset(_steps, p);
  });

  void _setAutosquash(bool on) => setState(() {
    if (!on) return _unfold();
    final r = autosquash(_steps);
    _steps = r.steps;
    _paired = r.pairs;
    // The pairing is the point; show it.
    _preset = null;
  });

  void _unfold() {
    _steps = undoAutosquash(_steps, widget.initial, _paired.keys.toSet());
    _paired = {};
  }

  void _setAction(int i, RebaseAction a) =>
      setState(() => _steps[i] = _steps[i].withAction(a));

  void _add(RebaseAction a) => setState(() {
    final id = '${_verb(a)}${++_added}';
    _steps.add(
      a == RebaseAction.exec
          ? RebaseStep.exec('', id: id)
          : RebaseStep.breakpoint(id: id),
    );
  });

  void _setCommand(int i, String c) =>
      setState(() => _steps[i] = RebaseStep.exec(c, id: _steps[i].id));

  void _remove(int i) => setState(() {
    _controllers.remove(_steps[i].id)?.dispose();
    _steps.removeAt(i);
  });

  /// Pops the plan — after showing every exec command in full and getting a
  /// yes, since each one runs as typed on the user's machine.
  Future<void> _start() async {
    final commands = [
      for (final s in _steps)
        if (s.action == RebaseAction.exec) s.command.trim(),
    ];
    if (commands.isNotEmpty && !await _confirmExec(commands)) return;
    if (!mounted) return;
    Navigator.of(context).pop(RebasePlan(_steps, updateRefs: _updateRefs));
  }

  Future<bool> _confirmExec(List<String> commands) async {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.rbExecConfirmTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.rbExecConfirmBody(commands.length),
                  style: TextStyle(color: t.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                for (final c in commands)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.bgApp,
                      border: Border.all(color: t.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      c,
                      style: AppFonts.mns(size: 12.5, color: t.textPrimary),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.rbExecConfirmRun),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _setMessage(int i, String m) =>
      _steps[i] = _steps[i].withAction(_steps[i].action, message: m);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final count = _steps.where((s) => s.isCommit).length;
    final onto = widget.onto;
    final error = rebasePlanError(_steps);
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
                      l.rbTitle,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    onto == null
                        ? l.rbCommitCount(count)
                        : l.rbCommitCountOnto(count, onto),
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
                    if (_autosquashable > 0 ||
                        widget.stackedBranches.isNotEmpty) ...[
                      Divider(height: 1, color: t.border),
                      if (_autosquashable > 0)
                        _OptionTile(
                          title: l.rbAutosquash,
                          subtitle: l.rbAutosquashHint(_autosquashable),
                          value: _autosquash,
                          onChanged: _setAutosquash,
                        ),
                      if (widget.stackedBranches.isNotEmpty)
                        _OptionTile(
                          title: l.rbUpdateRefs,
                          subtitle: l.rbUpdateRefsHint(
                            widget.stackedBranches.join(', '),
                          ),
                          value: _updateRefs,
                          onChanged: (v) => setState(() => _updateRefs = v),
                        ),
                    ],
                    if (_custom) ...[
                      Divider(height: 1, color: t.border),
                      _stepList(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _add(RebaseAction.exec),
                              icon: const Icon(Icons.terminal, size: 16),
                              label: Text(l.rbAddExec),
                            ),
                            TextButton.icon(
                              onPressed: () => _add(RebaseAction.breakpoint),
                              icon: const Icon(
                                Icons.pause_circle_outline,
                                size: 16,
                              ),
                              label: Text(l.rbAddBreak),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: t.border),
                      _legend(t, l),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  if (error != null)
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(color: t.danger, fontSize: 12),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.cancel),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    // git rejects an unrunnable todo *after* creating its state
                    // directory, leaving the repository mid-rebase, so the plan
                    // has to be refused here instead.
                    onPressed: error == null ? _start : null,
                    child: Text(l.rbStart),
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
        if (_steps[i].isCommit)
          _StepRow(
            key: ValueKey(_steps[i].id),
            index: i,
            step: _steps[i],
            controller: _controllerFor(_steps[i]),
            foldsInto: _foldTarget(_steps[i]),
            onAction: (a) => _setAction(i, a),
            onMessage: (m) => _setMessage(i, m),
          )
        else
          _ExtraStepRow(
            key: ValueKey(_steps[i].id),
            index: i,
            step: _steps[i],
            controller: _controllerFor(_steps[i]),
            onCommand: (c) => _setCommand(i, c),
            onRemove: () => _remove(i),
          ),
    ],
  );

  /// The subject of the commit [s] folds into, while autosquash paired it and
  /// it still folds.
  String? _foldTarget(RebaseStep s) {
    final target = _paired[s.id];
    if (target == null) return null;
    if (s.action != RebaseAction.fixup && s.action != RebaseAction.squash) {
      return null;
    }
    for (final t in _steps) {
      if (t.id == target) return t.message;
    }
    return null;
  }

  Widget _legend(AppTokens t, AppLocalizations l) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Text(
      [
        for (final a in RebaseAction.values)
          '${_verb(a)} — ${rebaseActionSummary(l, a)}',
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
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return RadioListTile<RebasePreset>(
      value: preset,
      enabled: enabled,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        _presetTitle(l, preset),
        style: TextStyle(
          color: enabled ? t.textPrimary : t.textFaint,
          fontSize: 13.5,
        ),
      ),
      subtitle: Text(
        enabled ? _presetSummary(l, preset, count) : l.rbNeedsTwo,
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
    final l = AppLocalizations.of(context);
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
        l.rbCustomize,
        style: TextStyle(color: t.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        l.rbCustomizeHint,
        style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final RebaseStep step;
  final TextEditingController controller;

  /// The subject of the commit autosquash folds this one into, if any.
  final String? foldsInto;
  final ValueChanged<RebaseAction> onAction;
  final ValueChanged<String> onMessage;
  const _StepRow({
    super.key,
    required this.index,
    required this.step,
    required this.controller,
    this.foldsInto,
    required this.onAction,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                for (final a in rebaseCommitActions)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      a.name,
                      style: TextStyle(color: t.textPrimary, fontSize: 12),
                    ),
                  ),
              ],
              items: [
                for (final a in rebaseCommitActions)
                  DropdownMenuItem(
                    value: a,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: a.name),
                          TextSpan(
                            text: ' — ${rebaseActionSummary(l, a)}',
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        step.message,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dropped ? t.textFaint : t.textMuted,
                          fontSize: 12.5,
                          decoration: dropped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (foldsInto != null)
                        Text(
                          l.rbFoldsInto(foldsInto!),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.accent, fontSize: 11.5),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A row that is not a commit: an exec with its command, or a break. Both can
/// be dragged like commits and removed again.
class _ExtraStepRow extends StatelessWidget {
  final int index;
  final RebaseStep step;
  final TextEditingController controller;
  final ValueChanged<String> onCommand;
  final VoidCallback onRemove;
  const _ExtraStepRow({
    super.key,
    required this.index,
    required this.step,
    required this.controller,
    required this.onCommand,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final exec = step.action == RebaseAction.exec;
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
            width: 64,
            child: Text(
              _verb(step.action),
              style: TextStyle(
                color: t.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: exec
                ? TextField(
                    key: ValueKey('rebase-exec-field-${step.id}'),
                    controller: controller,
                    onChanged: onCommand,
                    style: AppFonts.mns(size: 12.5, color: t.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.rbExecFieldHint,
                      border: const OutlineInputBorder(),
                    ),
                  )
                : Text(
                    rebaseActionSummary(l, step.action),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textMuted, fontSize: 12.5),
                  ),
          ),
          IconButton(
            tooltip: l.rbRemoveStep,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(Icons.close, color: t.textFaint),
          ),
        ],
      ),
    );
  }
}

/// An opt-in that changes how the whole rebase runs rather than what one
/// commit does.
class _OptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwitchListTile(
      dense: true,
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: TextStyle(color: t.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.35),
      ),
    );
  }
}
