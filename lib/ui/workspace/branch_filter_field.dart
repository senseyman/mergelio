import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/branch_filter.dart';

/// The filter box shown in the Branches section header. Focused when it
/// opens. Esc clears and closes it, the clear button only empties it, and an
/// empty box closes once focus leaves it.
class BranchFilterField extends ConsumerStatefulWidget {
  final String repoPath;
  const BranchFilterField({super.key, required this.repoPath});

  @override
  ConsumerState<BranchFilterField> createState() => _BranchFilterFieldState();
}

class _BranchFilterFieldState extends ConsumerState<BranchFilterField> {
  late final _controller = TextEditingController(
    text: ref.read(branchFilterProvider(widget.repoPath)),
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _controller.text.isEmpty) _close();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String v) =>
      ref.read(branchFilterProvider(widget.repoPath).notifier).state = v;

  void _close() {
    _set('');
    ref.read(branchFilterOpenProvider(widget.repoPath).notifier).state = false;
  }

  void _clear() {
    _controller.clear();
    _set('');
    // Kept focused, so the box stays open for the next query.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('sb-branch-filter'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              style: TextStyle(color: t.textPrimary, fontSize: 12),
              decoration: InputDecoration.collapsed(
                hintText: l.sbBranchFilter,
                hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
              ),
              onChanged: _set,
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: l.sbClearFilter,
                    icon: Icon(Icons.close, size: 12, color: t.textFaint),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(16, 16),
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _clear,
                  ),
          ),
        ],
      ),
    );
  }
}
