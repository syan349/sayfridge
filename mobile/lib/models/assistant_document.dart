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
          content: text.substring(title.start),
        );
      }
    }

    // Older inventory reports were saved as plain text with storage-space bullets.
    final legacyReport = RegExp(
      r'^(?:Inventory report[:：]?|库存报告[:：]?|There are \d+ in[- ]stock batches[:.]?)',
      caseSensitive: false,
    ).hasMatch(text);
    final bullets = RegExp(r'^\s*[-•]\s+', multiLine: true).allMatches(text);
    if (legacyReport && bullets.length >= 2) {
      return AssistantDocument(introduction: _leadIn(text), content: text);
    }
    return null;
  }

  static String _leadIn(String content) {
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(content)) {
      return content.contains('报告') ? '以下是为你整理的报告。' : '以下是为你整理的内容。';
    }
    return RegExp(
          r'\breport\b|in[- ]stock batches',
          caseSensitive: false,
        ).hasMatch(content)
        ? 'Here’s your report.'
        : 'Here’s what I’ve prepared for you.';
  }
}
