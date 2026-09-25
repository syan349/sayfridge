import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../theme/app_theme.dart';

abstract final class HomeAssets {
  static const root = 'assets/icons/home';
  static const avatar = '$root/default_avatar.png';
  static const guestExpiry = '$root/guest_expiry.png';
  static const noExpiry = '$root/no_expiry.png';
  static const filter = '$root/filter.png';
  static const search = '$root/search.png';
  static const setting = '$root/setting.png';
  static const titleLine = '$root/title_line.png';
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
            child: Image.asset(asset, width: size, height: size),
          ),
          Positioned(
            right: 1,
            top: 9,
            child: Transform.rotate(
              angle: -0.76,
              child: Container(
                width: 18,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 27,
            child: Transform.rotate(
              angle: -0.27,
              child: Container(
                width: 17,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String itemArtwork(InventoryItem item) {
  final name = item.itemDefinitionName.toLowerCase();
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    expiryLabel(item.expiryDate),
                    style: TextStyle(
                      fontSize: 14,
                      color: expiryColor(item.expiryDate),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View item', style: TextStyle(fontSize: 13)),
                      Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ],
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
    return SizedBox(
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          Positioned(
            left: 17,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 23),
              tooltip: 'Back',
            ),
          ),
        ],
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
