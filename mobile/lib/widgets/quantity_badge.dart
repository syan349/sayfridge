import 'package:flutter/material.dart';

abstract final class QuantityColors {
  static const estimatedText = Color(0xFF783C87);
  static const estimatedBackground = Color(0xFFF2EAF8);
  static const exactText = Color(0xFF3E4958);
  static const exactBackground = Color(0xFFEAEEF1);

  static Color text(bool estimated) => estimated ? estimatedText : exactText;
  static Color background(bool estimated) =>
      estimated ? estimatedBackground : exactBackground;
}

/// A quantity or its legend label, independent of expiry status.
class QuantityBadge extends StatelessWidget {
  const QuantityBadge({
    required this.text,
    required this.estimated,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    super.key,
  });

  final String text;
  final bool estimated;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: QuantityColors.background(estimated),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: QuantityColors.text(estimated),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    ),
  );
}

class QuantityLegend extends StatelessWidget {
  const QuantityLegend({super.key});

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        QuantityBadge(text: '≈ AI estimate', estimated: true, fontSize: 13),
        QuantityBadge(text: 'Exact', estimated: false, fontSize: 13),
      ],
    ),
  );
}
