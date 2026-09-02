import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tokens.dart';
import '../../domain/search.dart';
import '../../l10n/gen/app_localizations.dart';

/// One runnable entry in the command palette.
class PaletteCommand {
  final String label;
  final IconData icon;
  final Future<void> Function() run;
  const PaletteCommand(this.label, this.icon, this.run);
}

/// Fuzzy command launcher (⌘K). Type to filter; ↑/↓ move, Enter runs, Esc
/// closes.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteCommand> commands,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _Palette(commands: commands),
  );
}

class _Palette extends StatefulWidget {
  final List<PaletteCommand> commands;
  const _Palette({required this.commands});

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  var _query = '';
  var _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<PaletteCommand> get _results => _query.isEmpty
      ? widget.commands
      : fuzzyRank(_query, widget.commands, (c) => c.label);

  void _run(List<PaletteCommand> results) {
    if (results.isEmpty) return;
    final cmd = results[_selected.clamp(0, results.length - 1)];
    Navigator.of(context).pop();
    cmd.run();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e, int count) {
    if (e is! KeyDownEvent || count == 0) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _selected = (_selected + 1).clamp(0, count - 1));
        _revealSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _selected = (_selected - 1).clamp(0, count - 1));
        _revealSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // Keep the selected row visible during keyboard navigation. Rows are ~40px.
  void _revealSelected() {
    if (!_scroll.hasClients) return;
    const rowExtent = 40.0;
    final top = _selected * rowExtent;
    final viewTop = _scroll.offset;
    final viewBottom = viewTop + _scroll.position.viewportDimension;
    if (top < viewTop) {
      _scroll.jumpTo(top);
    } else if (top + rowExtent > viewBottom) {
      _scroll.jumpTo(top + rowExtent - _scroll.position.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final results = _results;
    if (_selected >= results.length) _selected = 0;

    return Align(
      alignment: const Alignment(0, -0.4),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(t.rCard),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: (n, e) => _onKey(n, e, results.length),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _selected = 0;
                  }),
                  onSubmitted: (_) => _run(results),
                  style: TextStyle(color: t.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: l.cpTypeCommand,
                    hintStyle: TextStyle(color: t.textFaint),
                    prefixIcon: Icon(
                      Icons.search,
                      color: t.textFaint,
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: t.border),
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final cmd = results[i];
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        cmd.run();
                      },
                      child: Container(
                        color: i == _selected ? t.active : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(cmd.icon, size: 15, color: t.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cmd.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
