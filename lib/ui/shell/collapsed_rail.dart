import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// What a collapsed left panel leaves behind: a narrow strip whose only job is
/// bringing the panel back. Shared by the history sidebar and the project
/// navigator so collapsing feels the same in both views.
class CollapsedRail extends StatelessWidget {
  final VoidCallback onExpand;
  const CollapsedRail({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: t.bgPanel,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            iconSize: 17,
            tooltip: 'Expand',
            icon: const Icon(Icons.chevron_right),
            onPressed: onExpand,
          ),
        ],
      ),
    );
  }
}
