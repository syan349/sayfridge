/// Presentation split only: the original conversation message remains unchanged.
class AssistantDocument {
  const AssistantDocument({required this.introduction, required this.content});

  final String introduction;
  final String content;

  static AssistantDocument? fromMessage(String message) {
    final text = message.replaceAll('\r\n', '\n').trim();
    final title = RegExp(
      r'^#{1,2}\s+[^\n]+$',
      multiLine: true,
    ).firstMatch(text);
    if (title != null) {
      final introduction = text.substring(0, title.start).trim();
      // A short lead-in followed by a document title is the generation format.
      // Ordinary answers and review/action cards keep their conversation layout.
      if (introduction.length <= 280 &&
          !RegExp(
            r'^\s*(?:[-*•]|\d+[.)])\s',
            multiLine: true,
          ).hasMatch(introduction)) {
        return AssistantDocument(
          introduction: introduction.isEmpty ? _leadIn(text) : introduction,
          content: _reportLayout(text.substring(title.start)),
        );
      }
    }

    // Older inventory reports were saved as plain text with storage-space bullets.
    final opening = text.split('\n').first.replaceAll('**', '').trim();
    final legacyReport = RegExp(
      r'^(?:Inventory report[:：]?|库存报告[:：]?|(?:There are|You have)\s+\d+\s+in[- ]stock\s+batch(?:es)?\b)',
      caseSensitive: false,
    ).hasMatch(opening);
    final bullets = RegExp(r'^\s*[-*•]\s+', multiLine: true).allMatches(text);
    if (legacyReport && bullets.isNotEmpty) {
      var content = _reportLayout(text);
      if (RegExp(
        r'^(?:Inventory report|库存报告)[:：]?$',
        caseSensitive: false,
      ).hasMatch(opening)) {
        content = content.substring(content.indexOf('\n') + 1).trimLeft();
      }
      final reportTitle = opening.startsWith('库存报告')
          ? '## 库存报告'
          : '## Inventory report';
      return AssistantDocument(
        introduction: _leadIn(text),
        content: '$reportTitle\n\n$content',
      );
    }
    return null;
  }

  static String _reportLayout(String text) {
    if (!RegExp(
      r'inventory report|in[- ]stock batch(?:es)?|库存报告',
      caseSensitive: false,
    ).hasMatch(text)) {
      return text;
    }
    final output = <String>[];
    final legacyGroups = !RegExp(r'^#{1,3}\s', multiLine: true).hasMatch(text);
    var number = 0;
    for (final line in text.split('\n')) {
      final group = RegExp(
        r'^\s*[-*•]\s+(?:\*\*)?([^:：]+?)(?:\*\*)?[:：](?:\*\*)?\s*(.+)$',
      ).firstMatch(line);
      if (legacyGroups && group != null) {
        output.add('\n### ${group[1]!.replaceAll('**', '').trim()}\n');
        number = 0;
        for (final item in _splitOutsideBrackets(group[2]!, ';；')) {
          output.add('${++number}. ${_boldItem(item)}');
        }
        output.add('');
        continue;
      }
      final other = RegExp(
        r'^Also recorded[:：]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (other != null) {
        output.add('\n### Other records\n');
        number = 0;
        for (final item in _splitOutsideBrackets(other[1]!, ',，')) {
          output.add(
            '${++number}. ${item.replaceFirst(RegExp(r'^and\s+', caseSensitive: false), '')}',
          );
        }
        continue;
      }
      if (RegExp(r'^#{1,3}\s').hasMatch(line)) number = 0;
      final item = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.+)$').firstMatch(line);
      output.add(item == null ? line : '${++number}. ${_boldItem(item[1]!)}');
    }
    return output.join('\n').trim();
  }

  static String _boldItem(String text) {
    if (text.startsWith('**')) return text;
    final separator = text.indexOf(' — ');
    return separator > 0
        ? '**${text.substring(0, separator)}**${text.substring(separator)}'
        : text;
  }

  static List<String> _splitOutsideBrackets(String text, String separators) {
    final parts = <String>[];
    var start = 0, depth = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if ('(（['.contains(char)) depth++;
      if (')）]'.contains(char)) depth = (depth - 1).clamp(0, text.length);
      if (depth == 0 && separators.contains(char)) {
        parts.add(text.substring(start, index).trim());
        start = index + 1;
      }
    }
    parts.add(text.substring(start).trim());
    return parts.where((part) => part.isNotEmpty).toList();
  }

  static String _leadIn(String content) {
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(content)) {
      return content.contains('报告') ? '以下是为你整理的报告。' : '以下是为你整理的内容。';
    }
    return RegExp(
          r'\breport\b|in[- ]stock batch(?:es)?',
          caseSensitive: false,
        ).hasMatch(content)
        ? 'Here’s your report.'
        : 'Here’s what I’ve prepared for you.';
  }
}
