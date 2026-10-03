import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/item_icon.dart';
import '../models/item_artwork_palette.dart';
import '../repositories/item_artwork_repository.dart';
import '../theme/app_theme.dart';
import 'inventory_card_trailing.dart';
import 'page_back_button.dart';
import 'quantity_badge.dart';
import 'expiry_display_scope.dart';

export 'quantity_badge.dart' show QuantityLegend;

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
  return ItemIcon.forName(itemName);
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

Color expiryColor(DateTime? expiryDate, {int daysBefore = 3, DateTime? asOf}) {
  if (expiryDate == null) return AppColors.muted;
  final days = DateUtils.dateOnly(
    expiryDate,
  ).difference(DateUtils.dateOnly(asOf ?? DateTime.now())).inDays;
  if (days <= daysBefore) return const Color(0xFFE75030);
  return const Color(0xFF388D38);
}

class InventoryArtwork extends StatefulWidget {
  const InventoryArtwork({
    required this.item,
    this.size = 58,
    this.artworkRepository = const ItemArtworkRepository(),
    super.key,
  });

  final InventoryItem item;
  final double size;
  final ItemArtworkRepository artworkRepository;

  @override
  State<InventoryArtwork> createState() => _InventoryArtworkState();
}

class _InventoryArtworkState extends State<InventoryArtwork> {
  late Future<String?> _artwork;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  void _loadArtwork() {
    // Storage may be unavailable in an offline preview or restricted browser.
    _artwork = widget.artworkRepository
        .read(widget.item.id)
        .catchError((Object _) => null);
  }

  @override
  void didUpdateWidget(covariant InventoryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item ||
        oldWidget.artworkRepository != widget.artworkRepository) {
      _loadArtwork();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return FutureBuilder<String?>(
      key: ValueKey(widget.item.id),
      future: _artwork,
      builder: (context, snapshot) {
        final asset = snapshot.data ?? itemArtwork(widget.item);
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.09),
          decoration: BoxDecoration(
            color: Color(ItemArtworkPalette.backgroundArgb(asset)),
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Image.asset(asset, fit: BoxFit.contain),
        );
      },
    );
  }
}

class InventoryItemTile extends StatelessWidget {
  const InventoryItemTile({
    required this.item,
    required this.onTap,
    this.selectionControl,
    this.selected = false,
    super.key,
  });

  final InventoryItem item;
  final VoidCallback onTap;
  final Widget? selectionControl;
  final bool selected;

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
            color: selected ? AppColors.primarySoft : null,
            border: Border.all(color: const Color(0xFFA8D589)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 300 ||
                  (MediaQuery.textScalerOf(context).scale(16) > 19 &&
                      constraints.maxWidth < 380);
              final trailing = InventoryCardTrailing(
                expiryText: expiryLabel(item.expiryDate),
                expiryColor: expiryColor(
                  item.expiryDate,
                  daysBefore: ExpiryDisplayScope.daysBeforeExpiryOf(context),
                ),
                action: selectionControl,
              );
              final quantity = QuantityBadge(
                text: quantityLabel(item),
                estimated: item.isEstimated,
              );
              final storage = Text(
                item.storageSpaceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      InventoryArtwork(item: item, size: 59),
                      const SizedBox(width: 10),
                      Container(
                        width: 1,
                        height: 58,
                        color: const Color(0xFFA8D589),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemDefinitionName,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 9),
                            if (compact)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [quantity, storage],
                              )
                            else
                              Row(
                                children: [
                                  Flexible(child: quantity),
                                  const Text(
                                    ' | ',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  Flexible(child: storage),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (!compact) ...[const SizedBox(width: 4), trailing],
                    ],
                  ),
                  if (compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class OverviewHeader extends StatelessWidget {
  const OverviewHeader({
    required this.title,
    this.actions,
    this.actionWidth = 48,
    super.key,
  });

  final String title;
  final Widget? actions;
  final double actionWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: actionWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: const PageBackButton(),
              ),
            ),
            Expanded(
              child: actions == null
                  ? Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            // Reserve equal space on both sides to keep the title centred.
            SizedBox(width: actionWidth, child: actions),
          ],
        ),
      ),
    );
  }
}
