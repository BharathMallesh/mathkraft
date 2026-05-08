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

  List<_Segment> _parse(String raw) {
    final segments = <_Segment>[];
    // Match $...$ (inline math) or \(...\) or \[...\]
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

    // No delimiters found — treat as pure math only if it has no spaces
    // (likely a short formula). Otherwise render as plain text.
    if (segments.isEmpty) {
      final hasSpaces = raw.contains(' ');
      segments.add(_Segment(raw, !hasSpaces));
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
        return Text(seg.content.trim(), style: style, softWrap: true);
      }
    }).toList();

    if (widgets.length == 1) return widgets.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets.map((w) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: w,
      )).toList(),
    );
  }
}

class _Segment {
  final String content;
  final bool isMath;
  _Segment(this.content, this.isMath);
}
