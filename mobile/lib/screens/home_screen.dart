import 'package:flutter/material.dart';

import '../widgets/app_background.dart';
import '../widgets/app_bottom_navigation.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onAssistantTap,
    this.onProfileTap,
    this.onLoginTap,
    this.onStorageSpacesTap,
    this.onSearchTap,
    this.onExpiringTap,
    this.onInventoryTap,
    this.isGuest = false,
    super.key,
  });

  final VoidCallback onAssistantTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLoginTap;
  final VoidCallback? onStorageSpacesTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExpiringTap;
  final VoidCallback? onInventoryTap;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(25, 40, 25, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good afternoon!',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            isGuest ? 'Guest Mode' : 'All Spaces',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (isGuest)
                            _GuestHomeContent(onLoginTap: onLoginTap)
                          else
                            _UserHomeContent(
                              onStorageSpacesTap: onStorageSpacesTap,
                              onSearchTap: onSearchTap,
                              onExpiringTap: onExpiringTap,
                              onInventoryTap: onInventoryTap,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 35,
                    right: 35,
                    bottom: 4,
                    child: AppBottomNavigation(
                      selectedDestination: AppNavigationDestination.home,
                      onAssistantTap: onAssistantTap,
                      onProfileTap: onProfileTap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestHomeContent extends StatelessWidget {
  const _GuestHomeContent({required this.onLoginTap});

  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Expiring soon',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 22),
        Icon(Icons.calendar_month_outlined, size: 72, color: primaryColor),
        const SizedBox(height: 14),
        const Text(
          'No item added yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Expiry reminders will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 28),
        Divider(color: primaryColor),
        const SizedBox(height: 24),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Inventory',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
            ),
            Text('0 items', style: TextStyle(fontSize: 21)),
          ],
        ),
        const SizedBox(height: 22),
        Icon(Icons.kitchen_outlined, size: 76, color: primaryColor),
        const SizedBox(height: 12),
        const Text(
          'Your inventory is empty',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add items to keep track of what you have.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 28),
        const Text(
          'Log in to start your own inventory.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onLoginTap,
            child: const Text(
              'Log in / Sign up',
              style: TextStyle(fontSize: 19),
            ),
          ),
        ),
      ],
    );
  }
}

class _UserHomeContent extends StatelessWidget {
  const _UserHomeContent({
    required this.onStorageSpacesTap,
    required this.onSearchTap,
    required this.onExpiringTap,
    required this.onInventoryTap,
  });

  final VoidCallback? onStorageSpacesTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onExpiringTap;
  final VoidCallback? onInventoryTap;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onStorageSpacesTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.white,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('All Spaces'),
                    Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'Search items ...',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 42),
        const Text(
          'Expiring soon',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 120,
              child: Column(
                children: [
                  Text(
                    '6',
                    style: TextStyle(
                      color: Color(0xFFD95228),
                      fontSize: 78,
                      height: 0.9,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Items',
                    style: TextStyle(color: Colors.grey, fontSize: 20),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 150, color: primaryColor),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                children: [
                  _ExpiringItemRow(
                    asset: 'assets/icons/inventory/milk.png',
                    name: 'Milk',
                    quantity: '750g',
                    location: 'Fridge',
                    daysLeft: '1 day left',
                  ),
                  Divider(),
                  _ExpiringItemRow(
                    asset: 'assets/icons/inventory/chicken_drumstick.png',
                    name: 'Chicken',
                    quantity: '≈ 500g',
                    location: 'Fridge',
                    daysLeft: '1 day left',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onExpiringTap,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: const Text('View all expiring items'),
          ),
        ),
        const SizedBox(height: 50),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Inventory',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w500),
            ),
            Text('12 items', style: TextStyle(fontSize: 21)),
          ],
        ),
        const SizedBox(height: 28),
        const Row(
          children: [
            Expanded(
              child: _InventoryCount(value: '3', label: 'Meat'),
            ),
            _CategoryDivider(),
            Expanded(
              child: _InventoryCount(value: '4', label: 'Vegetables'),
            ),
            _CategoryDivider(),
            Expanded(
              child: _InventoryCount(value: '5', label: 'Others'),
            ),
          ],
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: 260,
          child: FilledButton.icon(
            onPressed: onInventoryTap,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: const Text('View all items'),
          ),
        ),
      ],
    );
  }
}

class _ExpiringItemRow extends StatelessWidget {
  const _ExpiringItemRow({
    required this.asset,
    required this.name,
    required this.quantity,
    required this.location,
    required this.daysLeft,
  });

  final String asset;
  final String name;
  final String quantity;
  final String location;
  final String daysLeft;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(asset, width: 54, height: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 3),
              Text(
                '$quantity | $location',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
        Text(
          daysLeft,
          style: const TextStyle(color: Color(0xFFC66500), fontSize: 14),
        ),
      ],
    );
  }
}

class _InventoryCount extends StatelessWidget {
  const _InventoryCount({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 54, height: 1)),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    );
  }
}

class _CategoryDivider extends StatelessWidget {
  const _CategoryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 80,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
