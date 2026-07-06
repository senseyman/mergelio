import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// Titled panel shell used until each panel's real content lands.
class PanelPlaceholder extends StatelessWidget {
  final String title;
  final String hint;
  final Color background;
  final List<Widget> trailing;

  const PanelPlaceholder({
    super.key,
    required this.title,
    required this.hint,
    required this.background,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.only(left: 14, right: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                ...trailing,
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                hint,
                style: TextStyle(color: t.textFaint, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
