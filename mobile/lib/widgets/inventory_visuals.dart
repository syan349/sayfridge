import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../theme/app_theme.dart';
import 'inventory_card_trailing.dart';

abstract final class HomeAssets {
  static const root = 'assets/icons/home';
  static const avatar = '$root/default_avatar.png';
  static const guestExpiry = '$root/guest_expiry.png';
  static const noExpiry = '$root/expiry_all_clear.png';
  static const filter = '$root/filter.png';
  static const search = '$root/search.png';
  static const setting = '$root/setting.png';
  static const titleLine = '$root/title_line.png';
  static const morningLine = '$root/morning.png';
  static const eveningLine = '$root/evening.png';
  static const notificationEmpty = '$root/notification_empty.png';
  static const notificationUnread = '$root/notification_unread.png';
}

class HomeEmptyIllustration extends StatelessWidget {
  const HomeEmptyIllustration({
    required this.asset,
    required this.size,
    super.key,
  });

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 22,
      height: size + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 8,
            child: Image.asset(
              asset,
              width: size,
              height: size,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              // Mipmaps retain smooth edges when reducing the large source art.
              filterQuality: FilterQuality.medium,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EmptyIllustrationAccents(
                  diameter: size,
                  isExpiry: asset == HomeAssets.guestExpiry,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyIllustrationAccents extends CustomPainter {
  const _EmptyIllustrationAccents({
    required this.diameter,
    required this.isExpiry,
  });

  final double diameter;
  final bool isExpiry;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF85B85A)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    // Positions are relative to the circular artwork, matching each reference.
    Offset point(double x, double y) => Offset(x * diameter, 8 + y * diameter);
    if (isExpiry) {
      canvas.drawLine(point(.94, .12), point(1.07, -.01), paint);
      canvas.drawLine(point(1.015, .235), point(1.195, .186), paint);
    } else {
      canvas.drawLine(point(.965, .197), point(1.067, .099), paint);
      canvas.drawLine(point(1.026, .286), point(1.158, .253), paint);
    }
  }

  @override
  bool shouldRepaint(_EmptyIllustrationAccents oldDelegate) =>
      oldDelegate.diameter != diameter || oldDelegate.isExpiry != isExpiry;
}

String itemArtwork(InventoryItem item) {
  return itemArtworkForName(item.itemDefinitionName);
}

String itemArtworkForName(String itemName) {
  final name = itemName.toLowerCase();
  const icons = <String, String>{
    'chicken thigh': 'chicken_drumstick',
    'chicken drumstick': 'chicken_drumstick',
    'chicken breast': 'chicken_breast',
    'salmon': 'salmon_fillet',
    'tomato': 'tomato',
    'milk': 'milk',
    'beef': 'beef_tenderloin',
    'bacon': 'bacon',
    'eggplant': 'eggplant',
    'yogurt': 'yogurt',
    'yoghurt': 'yogurt',
    'egg': 'eggs',
    'cheese': 'cheese',
    'apple': 'apple',
    'banana': 'banana',
    'avocado': 'avocado',
    'broccoli': 'broccoli',
    'carrot': 'carrot',
    'potato': 'potato',
    'onion': 'onion',
    'lettuce': 'lettuce',
    'spinach': 'spinach',
    'mushroom': 'button_mushroom',
    'pork': 'pork_chop',
    'lamb': 'lamb_chop',
    'shrimp': 'shrimp',
    'crab': 'crab',
    'tuna': 'tuna_steak',
  };
  for (final entry in icons.entries) {
    if (name.contains(entry.key)) {
      return 'assets/icons/inventory/${entry.value}.png';
    }
  }
  return HomeAssets.avatar;
}

String quantityLabel(InventoryItem item) {
  final amount = item.displayAmount == item.displayAmount.truncateToDouble()
      ? item.displayAmount.toStringAsFixed(0)
      : item.displayAmount.toString();
  return '${item.isEstimated ? '≈ ' : ''}$amount ${item.displayUnit}';
}

String expiryLabel(DateTime? expiryDate) {
  if (expiryDate == null) return 'No expiry';
  final today = DateUtils.dateOnly(DateTime.now());
  final days = DateUtils.dateOnly(expiryDate).difference(today).inDays;
  if (days < 0) return '${-days} ${days == -1 ? 'day' : 'days'} overdue';
  if (days == 0) return 'Due today';
  return '$days ${days == 1 ? 'day' : 'days'} left';
}

Color expiryColor(DateTime? expiryDate) {
  if (expiryDate == null) return AppColors.muted;
  final days = DateUtils.dateOnly(
    expiryDate,
  ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
  if (days < 0) return const Color(0xFFE75030);
  if (days <= 2) return const Color(0xFFD75A20);
  return const Color(0xFF388D38);
}

class InventoryArtwork extends StatelessWidget {
  const InventoryArtwork({required this.item, this.size = 58, super.key});

  final InventoryItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.09),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7DF),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Image.asset(itemArtwork(item), fit: BoxFit.contain),
    );
  }
}

class InventoryItemTile extends StatelessWidget {
  const InventoryItemTile({required this.item, required this.onTap, super.key});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFA8D589)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              InventoryArtwork(item: item, size: 59),
              const SizedBox(width: 10),
              Container(width: 1, height: 58, color: const Color(0xFFA8D589)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemDefinitionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            quantityLabel(item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: item.isEstimated
                                  ? const Color(0xFFD75A20)
                                  : const Color(0xFF388D38),
                            ),
                          ),
                        ),
                        const Text(
                          ' | ',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        Flexible(
                          child: Text(
                            item.storageSpaceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              InventoryCardTrailing(
                expiryText: expiryLabel(item.expiryDate),
                expiryColor: expiryColor(item.expiryDate),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OverviewHeader extends StatelessWidget {
  const OverviewHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 23),
                tooltip: 'Back',
              ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Match the back button's width so the title stays page-centred.
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

class QuantityLegend extends StatelessWidget {
  const QuantityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        CircleAvatar(radius: 6, backgroundColor: Color(0xFF388D38)),
        SizedBox(width: 7),
        Text('Exact', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        SizedBox(width: 14),
        CircleAvatar(radius: 6, backgroundColor: Color(0xFFD75A20)),
        SizedBox(width: 7),
        Flexible(
          child: Text(
            'AI - Estimated',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
