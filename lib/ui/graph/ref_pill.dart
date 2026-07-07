import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';

/// Outline pill for a ref decoration on a graph row. Colour and icon follow
/// the ref kind: HEAD (success), local branch (accent), remote (muted),
/// tag (warning).
class RefPill extends StatelessWidget {
  final GitRef gitRef;
  const RefPill({super.key, required this.gitRef});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, icon) = switch (gitRef.kind) {
      RefKind.head => (t.success, null),
      RefKind.local => (t.accent, Icons.call_split),
      RefKind.remote => (t.textMuted, Icons.cloud_outlined),
      RefKind.tag => (t.warning, Icons.sell_outlined),
    };
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(icon, size: 10, color: color),
            )
          else
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          Text(
            gitRef.name,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
