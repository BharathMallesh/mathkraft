import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

// Renders a string that may contain both plain text and LaTeX math.
// Segments wrapped in $...$ are rendered as Math.tex.
// Everything else is rendered as a regular Text widget (spaces preserved).
class MathText extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final bool scrollable;

  const MathText({
    super.key,
    required this.text,
    this.textStyle,
    this.scrollable = true,
  });

  // Detects raw LaTeX commands like \frac, \sqrt, \alpha, etc.
  static final _latexCmdRegex = RegExp(r'\\(?:frac|sqrt|sum|int|alpha|beta|gamma|delta|epsilon|theta|lambda|mu|pi|sigma|omega|vec|hat|bar|dot|text|left|right|infty|times|cdot|leq|geq|neq|pm|mp|div|partial|nabla|forall|exists|in|subset|cup|cap|limits)[^a-zA-Z]');

  bool _hasRawLatex(String s) => _latexCmdRegex.hasMatch(s) || (s.contains('{') && s.contains('}') && s.contains('\\'));

  List<_Segment> _parse(String raw) {
    final segments = <_Segment>[];
    // Match $$...$$, $...$, \(...\), \[...\]
    final regex = RegExp(r'\$\$([^$]+)\$\$|\$([^$\n]+)\$|\\\((.+?)\\\)|\\\[(.+?)\\\]', dotAll: true);
    int cursor = 0;

    for (final m in regex.allMatches(raw)) {
      if (m.start > cursor) {
        segments.add(_Segment(raw.substring(cursor, m.start), false));
      }
      final mathContent = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
      segments.add(_Segment(mathContent.trim(), true));
      cursor = m.end;
    }

    if (cursor < raw.length) {
      segments.add(_Segment(raw.substring(cursor), false));
    }

    // No $ delimiters found — check for raw LaTeX commands (e.g. \frac, \sqrt)
    // This handles cases where AI returns LaTeX without $ wrappers
    if (segments.isEmpty || (segments.length == 1 && !segments[0].isMath)) {
      if (_hasRawLatex(raw)) {
        // Whole string contains LaTeX — render as math
        return [_Segment(raw.trim(), true)];
      }
      if (segments.isEmpty) {
        segments.add(_Segment(raw, false));
      }
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? const TextStyle(color: Colors.white, fontSize: 15);
    final segments = _parse(text);

    final widgets = segments.map<Widget>((seg) {
      if (seg.isMath) {
        final mathWidget = Math.tex(
          seg.content,
          textStyle: style,
          onErrorFallback: (err) => Text(seg.content, style: style),
        );
        return scrollable
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: mathWidget)
            : mathWidget;
      } else {
        return Text(seg.content, style: style, softWrap: true);
      }
    }).toList();

    if (widgets.length == 1) return widgets.first;

    // Use Wrap so text and math segments flow inline (left-to-right),
    // wrapping naturally — instead of stacking vertically in a Column.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      spacing: 2,
      children: widgets,
    );
  }
}

class _Segment {
  final String content;
  final bool isMath;
  _Segment(this.content, this.isMath);
}
