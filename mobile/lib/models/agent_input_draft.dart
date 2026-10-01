import 'agent_image.dart';

/// A text/photo draft that can move between entry points without losing images.
class AgentInputDraft {
  AgentInputDraft({required String text, List<AgentImage> images = const []})
    : text = text.trim(),
      images = List.unmodifiable(images);

  final String text;
  final List<AgentImage> images;

  bool get isEmpty => text.isEmpty && images.isEmpty;
}
