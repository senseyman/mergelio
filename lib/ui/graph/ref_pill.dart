import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/models.dart';

/// Outline pill for a ref decoration on a graph row. Colour and icon follow
/// the ref kind: HEAD (success), local branch (accent), remote (muted),
/// tag (warning).
class RefPill extends StatelessWidget {
  final GitRef gitRef;

  /// Cut a name too long for the available width with an ellipsis. Only for
  /// a parent that bounds the width, such as a [Wrap]; a graph row sizes the
  /// pill to its text.
  final bool ellipsize;
  const RefPill({super.key, required this.gitRef, this.ellipsize = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (color, icon) = switch (gitRef.kind) {
      RefKind.head => (t.success, null),
      RefKind.local => (t.accent, Icons.call_split),
      RefKind.remote => (t.textMuted, Icons.cloud_outlined),
      RefKind.tag => (t.warning, Icons.sell_outlined),
    };
    final label = Text(
      gitRef.name,
      maxLines: ellipsize ? 1 : null,
      overflow: ellipsize ? TextOverflow.ellipsis : null,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
      ),
    );
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
          if (ellipsize) Flexible(child: label) else label,
        ],
      ),
    );
  }
}
