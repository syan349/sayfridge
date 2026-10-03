import 'package:flutter/material.dart';

/// Mobile report typography, including readable legacy plain-text lists.
/// Formatting changes presentation only; saved messages retain their original text.
class AssistantMessageContent extends StatelessWidget {
  const AssistantMessageContent({
    required this.message,
    required this.textStyle,
    super.key,
  });

  final String message;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks(message);
    final bodyStyle = textStyle.copyWith(height: 1.45);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0)
            SizedBox(
              height:
                  blocks[i].paragraphBreak || blocks[i].kind == _Kind.heading
                  ? 14
                  : blocks[i - 1].kind == _Kind.heading
                  ? 8
                  : blocks[i].kind == _Kind.bullet &&
                        blocks[i - 1].kind == _Kind.bullet
                  ? 8
                  : 12,
            ),
          if (blocks[i].kind == _Kind.bullet)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(blocks[i].marker ?? '•', style: bodyStyle),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: _inline(blocks[i].text, emphasizeLabel: true),
                    ),
                    style: bodyStyle,
                    textWidthBasis: TextWidthBasis.longestLine,
                  ),
                ),
              ],
            )
          else
            Text.rich(
              TextSpan(children: _inline(blocks[i].text)),
              style: blocks[i].kind == _Kind.heading
                  ? bodyStyle.copyWith(
                      fontSize:
                          (textStyle.fontSize ?? 16) +
                          (blocks[i].level <= 2 ? 2 : 0),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    )
                  : bodyStyle,
              textWidthBasis: TextWidthBasis.longestLine,
            ),
        ],
      ],
    );
  }
}

enum _Kind { paragraph, heading, bullet }

class _Block {
  _Block(
    this.text, {
    this.kind = _Kind.paragraph,
    this.marker,
    this.level = 2,
    this.paragraphBreak = false,
  });

  String text;
  final _Kind kind;
  final String? marker;
  final int level;
  final bool paragraphBreak;
}

List<_Block> _blocks(String message) {
  final result = <_Block>[];
  final paragraph = <String>[];
  var paragraphBreak = false;
  void flush() {
    if (paragraph.isEmpty) return;
    result.add(_Block(paragraph.join('\n'), paragraphBreak: paragraphBreak));
    paragraph.clear();
    paragraphBreak = false;
  }

  for (final rawLine in message.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flush();
      paragraphBreak = true;
      continue;
    }
    final heading = RegExp(r'^#{1,3}\s+(.+?)\s*#*$').firstMatch(line);
    final bullet = RegExp(r'^(?:[-*•]\s+|(\d+[.)])\s+)(.+)$').firstMatch(line);
    final plainHeading =
        line.length <= 80 &&
        (line.endsWith(':') || line.endsWith('：')) &&
        bullet == null;
    final boldHeading = RegExp(r'^\*\*[^*]+\*\*[:：]?$').hasMatch(line);
    if (heading != null || plainHeading || boldHeading) {
      flush();
      result.add(
        _Block(
          heading?.group(1) ?? line,
          kind: _Kind.heading,
          level: heading == null ? 3 : line.indexOf(' '),
          paragraphBreak: paragraphBreak,
        ),
      );
      paragraphBreak = false;
    } else if (bullet != null) {
      flush();
      result.add(
        _Block(
          bullet.group(2)!,
          kind: _Kind.bullet,
          marker: bullet.group(1) ?? '•',
          paragraphBreak: paragraphBreak,
        ),
      );
      paragraphBreak = false;
    } else if (!paragraphBreak &&
        paragraph.isEmpty &&
        rawLine.startsWith(RegExp(r'\s{2,}')) &&
        result.isNotEmpty &&
        result.last.kind == _Kind.bullet) {
      result.last.text += ' $line';
    } else {
      paragraph.add(line);
    }
  }
  flush();
  return result;
}

List<InlineSpan> _inline(String text, {bool emphasizeLabel = false}) {
  final spans = <InlineSpan>[];
  // Existing reports often use "Space name: details" without Markdown.
  if (emphasizeLabel && !text.startsWith('**')) {
    final label = RegExp(r'^([^:：\n]{1,60}[:：])\s*').firstMatch(text);
    if (label != null) {
      spans.add(
        TextSpan(
          text: label.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      spans.add(const TextSpan(text: ' '));
      text = text.substring(label.end);
    }
  }
  var cursor = 0;
  for (final match in RegExp(
    r'\*\*([^*]+)\*\*|__([^_]+)__|`([^`]+)`',
  ).allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(1) ?? match.group(2) ?? match.group(3),
        style: TextStyle(
          fontWeight: match.group(3) == null ? FontWeight.w700 : null,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
