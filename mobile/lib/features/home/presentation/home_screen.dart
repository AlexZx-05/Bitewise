import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../insights/presentation/insights_screen.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../scanner/data/meal_scan_repository.dart';
import 'meal_dashboard_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final pageIndex = switch (_selectedTab) {
      1 => 1,
      3 => 2,
      4 => 3,
      _ => 0,
    };
    final pages = [
      _HomeContent(
        onScanner: () => context.push('/scan'),
        onPackagedScan: () => context.push('/scan/packaged'),
        onMealScan: () => _openMeal(),
        onDiary: () => setState(() => _selectedTab = 1),
        onProfile: () => setState(() => _selectedTab = 4),
      ),
      MealDashboardScreen(onAddMeal: (mealType) => _openMeal(mealType)),
      InsightsScreen(onCompareProduct: () => context.push('/scan/packaged')),
      ProfileScreen(onDiary: () => setState(() => _selectedTab = 1)),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: pageIndex, children: pages),
      ),
      bottomNavigationBar: _FoodScanBottomNavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          if (index == 2) {
            context.push('/scan');
          } else {
            setState(() => _selectedTab = index);
          }
        },
      ),
    );
  }

  Future<void> _openMeal([String? mealType]) async {
    final path = mealType == null ? '/scan/meal' : '/scan/meal?type=$mealType';
    final saved = await context.push<bool>(path);
    if (saved == true) {
      ref.invalidate(mealDiaryProvider(todayMealDiaryKey()));
    }
  }
}

class _FoodScanBottomNavigationBar extends StatelessWidget {
  const _FoodScanBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _selectedColor = Color(0xFF005A38);
  static const _scannerOverlap = 29.0;
  static const _barContentHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _scannerOverlap + _barContentHeight,
        child: Stack(
          children: [
            Positioned(
              top: _scannerOverlap,
              left: 0,
              right: 0,
              bottom: 0,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFFEF8),
                  border: Border(top: BorderSide(color: Color(0xFFE5E7E4))),
                ),
              ),
            ),
            Positioned(
              top: _scannerOverlap,
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BottomNavigationItem(
                    label: 'Home',
                    icon: selectedIndex == 0
                        ? Icons.home_rounded
                        : Icons.home_outlined,
                    selected: selectedIndex == 0,
                    onTap: () => onDestinationSelected(0),
                  ),
                  _BottomNavigationItem(
                    label: 'Diary',
                    icon: Icons.menu_book_outlined,
                    selected: selectedIndex == 1,
                    onTap: () => onDestinationSelected(1),
                  ),
                  _BottomNavigationItem(
                    label: 'Scan',
                    icon: Icons.document_scanner_outlined,
                    selected: false,
                    onTap: () => onDestinationSelected(2),
                    scanner: true,
                  ),
                  _BottomNavigationItem(
                    label: 'Insights',
                    icon: selectedIndex == 3
                        ? Icons.bar_chart_rounded
                        : Icons.bar_chart_outlined,
                    selected: selectedIndex == 3,
                    onTap: () => onDestinationSelected(3),
                  ),
                  _BottomNavigationItem(
                    label: 'Profile',
                    icon: Icons.person_outline_rounded,
                    selected: selectedIndex == 4,
                    onTap: () => onDestinationSelected(4),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Semantics(
                  button: true,
                  label: 'Open Scanner',
                  child: Material(
                    color: _selectedColor,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: _selectedColor.withValues(alpha: 0.28),
                    child: InkWell(
                      onTap: () => onDestinationSelected(2),
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 58,
                        height: 58,
                        child: Icon(
                          Icons.document_scanner_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.scanner = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool scanner;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF005A38)
        : const Color(0xFF687078);

    return Expanded(
      child: Semantics(
        button: true,
        enabled: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 5, 2, 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  child: Center(
                    child: scanner
                        ? const SizedBox(width: 44, height: 32)
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: selected ? 56 : 44,
                            height: 32,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFE5F0E9)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(icon, color: color, size: 23),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.onScanner,
    required this.onPackagedScan,
    required this.onMealScan,
    required this.onDiary,
    required this.onProfile,
  });

  final VoidCallback onScanner;
  final VoidCallback onPackagedScan;
  final VoidCallback onMealScan;
  final VoidCallback onDiary;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 12 => 'Good morning!',
      < 17 => 'Good afternoon!',
      _ => 'Good evening!',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final compact = screenHeight < 900 || constraints.maxHeight < 760;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                22,
                compact ? 8 : 16,
                22,
                compact ? 12 : 28,
              ),
              children: [
                _DashboardHeader(
                  greeting: greeting,
                  onProfile: onProfile,
                  compact: compact,
                ),
                SizedBox(height: compact ? 10 : 22),
                _GoalSummary(profile: profile, compact: compact),
                SizedBox(height: compact ? 10 : 18),
                _ScanCard(onScan: onScanner, compact: compact),
                SizedBox(height: compact ? 10 : 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FoodScanShortcut(
                        title: 'Packaged food',
                        subtitle: 'Scan nutrition labels',
                        illustration: _PackagedFoodIllustration(
                          compact: compact,
                        ),
                        onTap: onPackagedScan,
                        compact: compact,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FoodScanShortcut(
                        title: 'Home-cooked meal',
                        subtitle: 'Identify your dish',
                        illustration: _MealFoodIllustration(compact: compact),
                        onTap: onMealScan,
                        compact: compact,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 22),
                _NutritionSummary(onDiary: onDiary, compact: compact),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.onProfile,
    required this.compact,
  });

  final String greeting;
  final VoidCallback onProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0xFFEAF6EC),
          child: Icon(Icons.eco_outlined, color: AppTheme.green, size: 27),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FOODSCAN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                greeting,
                style:
                    (compact
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(
                          color: const Color(0xFF101C2E),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onProfile,
          tooltip: 'Open profile',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF0EFE9),
            foregroundColor: AppTheme.green,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.person_outline_rounded),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF101C2E),
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.charcoal.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.profile, required this.compact});

  final AsyncValue<Profile> profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final goalLabel = profile.asData?.value.goalLabel;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 17,
        vertical: compact ? 10 : 13,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.track_changes_rounded,
            color: AppTheme.green,
            size: 23,
          ),
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
  const _ScanCard({required this.onScan, required this.compact});

  final VoidCallback onScan;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 12 : 25,
        compact ? 18 : 22,
        compact ? 12 : 22,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00502F), Color(0xFF003F27), Color(0xFF00603A)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.green.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: compact ? 62 : 104,
            height: compact ? 62 : 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF65C99A), width: 2),
              color: Colors.white.withValues(alpha: 0.04),
            ),
            child: Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: compact ? 34 : 52,
            ),
          ),
          SizedBox(height: compact ? 5 : 16),
          Text(
            'Scan your food',
            textAlign: TextAlign.center,
            style:
                (compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
          ),
          SizedBox(height: compact ? 2 : 8),
          Text(
            'Check packaged labels or understand your everyday meals.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: compact ? 12 : 14,
              height: compact ? 1.2 : 1.45,
            ),
          ),
          SizedBox(height: compact ? 6 : 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScan,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF075C38),
                minimumSize: Size.fromHeight(compact ? 38 : 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                size: compact ? 18 : 24,
              ),
              label: const Text('Open Scanner'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionSummary extends ConsumerWidget {
  const _NutritionSummary({required this.onDiary, required this.compact});

  final VoidCallback onDiary;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(mealDiaryProvider(todayMealDiaryKey()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeading(
                title: "Today's summary",
                subtitle: compact ? null : 'Based on meals you have saved',
              ),
            ),
            TextButton(
              onPressed: onDiary,
              style: compact
                  ? TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(48, 36),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
              child: const Text('View diary'),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 12),
        diary.when(
          loading: () => _NutritionStateCard(
            compact: compact,
            child: Center(
              child: SizedBox(
                width: compact ? 18 : 22,
                height: compact ? 18 : 22,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, stackTrace) => _NutritionStateCard(
            compact: compact,
            child: Row(
              children: [
                const Icon(Icons.cloud_off_outlined, color: AppTheme.green),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Today’s nutrition could not be loaded. Open your diary '
                    'to retry.',
                    style: TextStyle(height: 1.35),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ref.invalidate(mealDiaryProvider(todayMealDiaryKey())),
                  tooltip: 'Retry loading nutrition',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          data: (meals) {
            final calories = _nutritionTotal(meals, 'energy_kcal');
            final protein = _nutritionTotal(meals, 'protein_g');
            final carbs = _nutritionTotal(meals, 'carbohydrates_g');
            final fat = _nutritionTotal(meals, 'total_fat_g');
            return _NutritionStateCard(
              compact: compact,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(
                        Icons.local_fire_department_outlined,
                        color: AppTheme.green,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        calories == null ? '—' : calories.round().toString(),
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.titleLarge
                                    : Theme.of(
                                        context,
                                      ).textTheme.headlineMedium)
                                ?.copyWith(
                                  color: const Color(0xFF101C2E),
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          'kcal',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppTheme.charcoal.withValues(
                                  alpha: 0.68,
                                ),
                              ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${meals.length} ${meals.length == 1 ? 'meal' : 'meals'}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 6 : 16),
                  const Divider(height: 1),
                  SizedBox(height: compact ? 6 : 14),
                  Row(
                    children: [
                      _NutritionMacro(
                        label: 'Protein',
                        grams: protein,
                        compact: compact,
                      ),
                      _NutritionMacro(
                        label: 'Carbs',
                        grams: carbs,
                        compact: compact,
                      ),
                      _NutritionMacro(
                        label: 'Fat',
                        grams: fat,
                        compact: compact,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  double? _nutritionTotal(List<MealScanResult> meals, String key) {
    if (meals.isEmpty) return 0;
    if (meals.any((meal) => !meal.nutritionTotals.containsKey(key))) {
      return null;
    }
    return meals.fold<double>(
      0,
      (total, meal) => total + (_toNumber(meal.nutritionTotals[key]) ?? 0),
    );
  }

  double? _toNumber(Object? value) {
    if (value is num) return value.isFinite ? value.toDouble() : null;
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }
}

class _NutritionStateCard extends StatelessWidget {
  const _NutritionStateCard({required this.child, required this.compact});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAE9E3)),
      ),
      child: child,
    );
  }
}

class _NutritionMacro extends StatelessWidget {
  const _NutritionMacro({
    required this.label,
    required this.grams,
    required this.compact,
  });

  final String label;
  final double? grams;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gramsValue = grams;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.charcoal.withValues(alpha: 0.65),
              fontSize: compact ? 10 : null,
            ),
          ),
          SizedBox(height: compact ? 1 : 4),
          Text(
            gramsValue == null ? '— g' : '${gramsValue.round()} g',
            style:
                (compact
                        ? Theme.of(context).textTheme.bodyMedium
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(
                      color: const Color(0xFF101C2E),
                      fontWeight: FontWeight.w800,
                    ),
          ),
        ],
      ),
    );
  }
}

class _FoodScanShortcut extends StatelessWidget {
  const _FoodScanShortcut({
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.onTap,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final Widget illustration;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFEAE9E3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 10,
            compact ? 7 : 12,
            compact ? 8 : 10,
            compact ? 8 : 14,
          ),
          child: Column(
            children: [
              SizedBox(height: compact ? 42 : 76, child: illustration),
              SizedBox(height: compact ? 5 : 10),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF101C2E),
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.charcoal.withValues(alpha: 0.68),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackagedFoodIllustration extends StatelessWidget {
  const _PackagedFoodIllustration({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Container(
          width: compact ? 32 : 48,
          height: compact ? 38 : 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF4D995), Color(0xFFE9BE65)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD5AB53)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: compact ? 5 : 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFD8B45F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                ),
              ),
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.eco_rounded,
                    color: Color(0xFF17613E),
                    size: compact ? 17 : 22,
                  ),
                ),
              ),
              Container(
                margin: EdgeInsets.fromLTRB(
                  compact ? 5 : 7,
                  0,
                  compact ? 5 : 7,
                  compact ? 5 : 7,
                ),
                height: compact ? 3 : 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF17613E).withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MealFoodIllustration extends StatelessWidget {
  const _MealFoodIllustration({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/images/food__welcome.png',
        width: double.infinity,
        cacheWidth: compact ? 200 : 320,
        fit: BoxFit.cover,
        alignment: const Alignment(0.55, -0.35),
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xFFEAF6EC),
          child: Center(
            child: Icon(
              Icons.ramen_dining_rounded,
              size: 36,
              color: AppTheme.green,
            ),
          ),
        ),
      ),
    );
  }
}
