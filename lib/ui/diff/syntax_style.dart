import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../domain/git/diff.dart';

/// Past this many characters the editor shows plain text. Every keystroke
/// rebuilds the whole span tree, and tokenising a file this large that often
/// costs more than the colour is worth.
const maxHighlightChars = 128 * 1024;

Color syntaxColor(AppTokens t, SyntaxKind k) => switch (k) {
  SyntaxKind.keyword => t.accent,
  SyntaxKind.string => t.success,
  SyntaxKind.number => t.warning,
  SyntaxKind.comment => t.textFaint,
  SyntaxKind.plain => t.textPrimary,
};

/// Highlighted spans for [text], using the same tokeniser as the diff view.
///
/// The concatenation of every span's text is [text] character for character.
/// A text field maps caret and selection offsets through these spans, so
/// dropping or reordering even one character would misplace the cursor.
TextSpan syntaxSpans(String text, TextStyle base, AppTokens t) {
  if (text.length > maxHighlightChars) return TextSpan(text: text, style: base);

  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final tok in highlightLine(lines[i])) {
      spans.add(
        TextSpan(
          text: tok.text,
          style: base.copyWith(color: syntaxColor(t, tok.kind)),
        ),
      );
    }
    // split() drops the separators; put them back so offsets still line up.
    if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
  }
  return TextSpan(style: base, children: spans);
}

/// A text controller that paints its contents with [syntaxSpans].
class SyntaxHighlightingController extends TextEditingController {
  /// Not final: the theme can change while the editor is open, and the next
  /// rebuild should paint in the new colours.
  AppTokens tokens;

  SyntaxHighlightingController({required this.tokens, super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Mid-composition (IME) text needs the base implementation's underline to
    // show which characters are still provisional.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return syntaxSpans(text, style ?? const TextStyle(), tokens);
  }
}
