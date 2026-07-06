import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// Small square icon button used across the chrome bars.
class BarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const BarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: active ? t.active : Colors.transparent,
        borderRadius: BorderRadius.circular(t.rButton),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.rButton),
          hoverColor: t.hover,
          onTap: onPressed,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 17,
              color: onPressed == null
                  ? t.textFaint
                  : (active ? t.accent : t.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled bar button (icon + text) for the bottom action bar.
class BarTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const BarTextButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.rButton),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.rButton),
        hoverColor: t.hover,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: onPressed == null ? t.textFaint : t.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: onPressed == null ? t.textFaint : t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin vertical divider between control groups.
class BarSeparator extends StatelessWidget {
  const BarSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: context.tokens.border,
  );
}
