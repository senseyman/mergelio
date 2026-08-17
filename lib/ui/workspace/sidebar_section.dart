import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// A collapsible sidebar group: header (chevron · icon · LABEL · count) with
/// its rows beneath, or an empty-state line when it has none.
class SidebarSection extends StatelessWidget {
  final String id;
  final IconData icon;
  final String label;
  final int count;
  final bool open;
  final String emptyLabel;
  final VoidCallback onToggle;
  final List<Widget> children;

  /// Optional action shown at the right of the header, e.g. an add button.
  final Widget? trailing;

  const SidebarSection({
    super.key,
    required this.id,
    required this.icon,
    required this.label,
    required this.count,
    required this.emptyLabel,
    required this.open,
    required this.onToggle,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          hoverColor: t.hover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 4),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: t.textFaint,
                ),
                const SizedBox(width: 2),
                Icon(icon, size: 14, color: t.textMuted),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(color: t.textFaint, fontSize: 11),
                ),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
        ),
        if (open && children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 12, 4),
            child: Text(
              emptyLabel,
              style: TextStyle(color: t.textFaint, fontSize: 12),
            ),
          ),
        if (open) ...children,
      ],
    );
  }
}
