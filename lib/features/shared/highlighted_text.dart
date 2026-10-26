import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/search.dart';

/// Text with the words from a [SearchQuery] emphasised: bold on a soft accent
/// tint, so it never relies on colour alone. With no query it is plain text.
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    this.query,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final SearchQuery? query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ranges = query?.highlights(text) ?? const <(int, int)>[];
    if (ranges.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    final c = context.appColors;
    final mark = TextStyle(
      fontWeight: FontWeight.w700,
      backgroundColor: c.accent.withValues(alpha: 0.22),
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: mark));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
