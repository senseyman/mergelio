import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// Floating chip that follows the pointer while a branch is dragged.
class BranchDragChip extends StatelessWidget {
  final String label;
  const BranchDragChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 12, color: t.accent),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: t.textPrimary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
