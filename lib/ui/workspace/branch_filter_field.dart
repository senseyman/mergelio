import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/branch_filter.dart';

/// The filter box at the top of the Branches section. Stateful for its
/// controller, so the controller is disposed with the field rather than on a
/// rebuild. Esc or the clear button empties it.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String v) =>
      ref.read(branchFilterProvider(widget.repoPath).notifier).state = v;

  void _clear() {
    _controller.clear();
    _set('');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 12, 6),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
        child: TextField(
          key: const ValueKey('sb-branch-filter'),
          controller: _controller,
          style: TextStyle(color: t.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: l.sbBranchFilter,
            hintStyle: TextStyle(color: t.textFaint, fontSize: 12),
            prefixIcon: Icon(Icons.search, size: 14, color: t.textFaint),
            prefixIconConstraints: const BoxConstraints(minWidth: 22),
            suffixIcon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: l.sbClearFilter,
                      icon: Icon(Icons.close, size: 12, color: t.textFaint),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _clear,
                    ),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 22),
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
          ),
          onChanged: _set,
        ),
      ),
    );
  }
}
