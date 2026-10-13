import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeContent(
        onScanner: () => context.push('/scan'),
        onPackagedScan: () => context.push('/scan/packaged'),
        onMealScan: () => context.push('/scan/meal'),
      ),
      const _EmptySection(
        icon: Icons.menu_book_outlined,
        title: 'Your food diary',
        description:
            'Your food activity will appear here after scanning is added.',
      ),
      const _ProfileSection(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedTab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Diary',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.onScanner,
    required this.onPackagedScan,
    required this.onMealScan,
  });

  final VoidCallback onScanner;
  final VoidCallback onPackagedScan;
  final VoidCallback onMealScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
      children: [
        Row(
          children: [
            const Icon(Icons.eco_outlined, color: AppTheme.green, size: 28),
            const SizedBox(width: 9),
            Text(
              'FOODSCAN',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.green,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Your food companion',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.green,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Make your next food choice an informed one.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 22),
        _GoalSummary(profile: profile),
        const SizedBox(height: 18),
        _ScanCard(onScan: onScanner),
        const SizedBox(height: 24),
        Text(
          'What are you eating?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _FoodTypeTile(
          icon: Icons.inventory_2_outlined,
          title: 'Packaged food',
          subtitle: 'Ingredients and nutrition label',
          onTap: onPackagedScan,
        ),
        const SizedBox(height: 10),
        _FoodTypeTile(
          icon: Icons.ramen_dining_outlined,
          title: 'Home-cooked meal',
          subtitle: 'Understand an everyday meal',
          onTap: onMealScan,
        ),
        const SizedBox(height: 24),
        Text(
          'Your food activity',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const _EmptyActivity(),
      ],
    );
  }
}

class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.profile});

  final AsyncValue<Profile> profile;

  @override
  Widget build(BuildContext context) {
    final goalLabel = profile.asData?.value.goalLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.sage,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              goalLabel == null
                  ? 'Your goal is not set'
                  : 'Your goal: $goalLabel',
              style: const TextStyle(
                color: AppTheme.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.green,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.center_focus_strong, color: Colors.white, size: 30),
          const SizedBox(height: 16),
          Text(
            'Scan your food',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Check packaged labels or learn about everyday meals.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onScan,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.green,
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Open scanner'),
          ),
        ],
      ),
    );
  }
}

class _FoodTypeTile extends StatelessWidget {
  const _FoodTypeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: CircleAvatar(
          backgroundColor: AppTheme.sage,
          foregroundColor: AppTheme.green,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppTheme.green, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your scans will appear here. Start with a food label when scanning is available.',
                style: TextStyle(
                  color: AppTheme.charcoal.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(profileProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (value) => _EmptySection(
        icon: Icons.person_outline,
        title: value.displayName ?? 'Your profile',
        description:
            'Goal: ${value.goalLabel ?? 'Not set'}\n'
            'Profile details and nutrition targets can be added later.',
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.sage,
              foregroundColor: AppTheme.green,
              child: Icon(icon, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.charcoal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                color: AppTheme.charcoal.withValues(alpha: 0.72),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
