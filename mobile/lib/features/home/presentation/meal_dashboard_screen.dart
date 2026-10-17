import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scanner/data/meal_scan_repository.dart';

class MealDashboardScreen extends ConsumerStatefulWidget {
  const MealDashboardScreen({required this.onAddMeal, super.key});

  final Future<void> Function(String?) onAddMeal;

  @override
  ConsumerState<MealDashboardScreen> createState() => _MealDashboardScreenState();
}

class _MealDashboardScreenState extends ConsumerState<MealDashboardScreen> {
  DateTime _selectedDate = DateTime.now();

  String get _diaryKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _DiaryColors.forest,
          ),
        ),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  Future<void> _addMeal(String? mealType) async {
    if (!DateUtils.isSameDay(_selectedDate, DateTime.now())) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Meal logging is available for today’s diary.'),
          ),
        );
      return;
    }
    await widget.onAddMeal(mealType);
    if (mounted) ref.invalidate(mealDiaryProvider(_diaryKey));
  }

  @override
  Widget build(BuildContext context) {
    final diaryKey = _diaryKey;
    final diary = ref.watch(mealDiaryProvider(diaryKey));
    return diary.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _DiaryColors.forest),
      ),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 38,
                color: _DiaryColors.forest,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load meals for $_diaryKey.\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(mealDiaryProvider(diaryKey)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (meals) => _MealDiaryContent(
        meals: meals,
        selectedDate: _selectedDate,
        onSelectDate: _selectDate,
        onAddMeal: _addMeal,
        onRefresh: () async => ref.invalidate(mealDiaryProvider(diaryKey)),
      ),
    );
  }
}

class _MealDiaryContent extends StatelessWidget {
  const _MealDiaryContent({
    required this.meals,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onAddMeal,
    required this.onRefresh,
  });

  final List<MealScanResult> meals;
  final DateTime selectedDate;
  final VoidCallback onSelectDate;
  final Future<void> Function(String?) onAddMeal;
  final Future<void> Function() onRefresh;

  static const _mealTypes = [
    _MealType(
      key: 'breakfast',
      label: 'Breakfast',
      suggestion: 'Add your breakfast',
      subtitle: 'A healthy start to your day',
      icon: Icons.wb_twilight_rounded,
      tint: Color(0xFFFFF0BD),
      accent: Color(0xFFB78100),
    ),
    _MealType(
      key: 'lunch',
      label: 'Lunch',
      suggestion: 'Add your lunch',
      subtitle: 'Keep your energy going',
      icon: Icons.wb_sunny_rounded,
      tint: Color(0xFFDFF4D3),
      accent: Color(0xFF39804B),
    ),
    _MealType(
      key: 'dinner',
      label: 'Dinner',
      suggestion: 'Add your dinner',
      subtitle: 'End your day mindfully',
      icon: Icons.nights_stay_rounded,
      tint: Color(0xFFEEE2F7),
      accent: Color(0xFF7350A1),
    ),
    _MealType(
      key: 'snack',
      label: 'Snacks',
      suggestion: 'Add a snack',
      subtitle: 'A little something between meals',
      icon: Icons.cookie_outlined,
      tint: Color(0xFFFCE7D9),
      accent: Color(0xFFB56937),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final dense = constraints.maxHeight < 760;
        final horizontalPadding = compact ? 14.0 : 22.0;
        final mealsByType = {
          for (final type in _mealTypes)
            type.key: meals.where((meal) => meal.mealType == type.key).toList(),
        };

        return RefreshIndicator(
          color: _DiaryColors.forest,
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              dense ? 8 : 14,
              horizontalPadding,
              dense ? 10 : 20,
            ),
            children: [
              _DiaryHeader(
                date: selectedDate,
                compact: compact,
                dense: dense,
                onSelectDate: onSelectDate,
              ),
              SizedBox(height: dense ? 8 : 14),
              _DailySummary(
                calories: _total('energy_kcal'),
                protein: _total('protein_g'),
                carbs: _total('carbohydrates_g'),
                fat: _total('total_fat_g'),
                compact: compact,
                dense: dense,
              ),
              SizedBox(height: dense ? 8 : 12),
              _AddMealButton(
                compact: compact,
                onPressed: () => onAddMeal(null),
              ),
              SizedBox(height: dense ? 8 : 14),
              for (final (index, type) in _mealTypes.indexed) ...[
                _MealSectionCard(
                  type: type,
                  meals: mealsByType[type.key]!,
                  calories: _mealCalories(mealsByType[type.key]!),
                  compact: compact,
                  dense: dense,
                  onAddMeal: onAddMeal,
                ),
                if (index < _mealTypes.length - 1)
                  SizedBox(height: dense ? 6 : 10),
              ],
            ],
          ),
        );
      },
    );
  }

  double? _total(String nutrient) {
    if (meals.isEmpty) return 0;
    if (meals.any((meal) => !meal.nutritionTotals.containsKey(nutrient))) {
      return null;
    }
    return meals.fold<double>(
      0,
      (sum, meal) => sum + (_number(meal.nutritionTotals[nutrient]) ?? 0),
    );
  }

  double? _mealCalories(List<MealScanResult> typeMeals) {
    if (typeMeals.isEmpty) return 0;
    if (typeMeals.any(
      (meal) => !meal.nutritionTotals.containsKey('energy_kcal'),
    )) {
      return null;
    }
    return typeMeals.fold<double>(
      0,
      (sum, meal) =>
          sum + (_number(meal.nutritionTotals['energy_kcal']) ?? 0),
    );
  }
}

class _DiaryHeader extends StatelessWidget {
  const _DiaryHeader({
    required this.date,
    required this.compact,
    required this.dense,
    required this.onSelectDate,
  });

  final DateTime date;
  final bool compact;
  final bool dense;
  final VoidCallback onSelectDate;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(date, DateTime.now());
    final dateLabel =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your meals',
                style: TextStyle(
                  color: _DiaryColors.ink,
                  fontSize: dense ? 30 : compact ? 32 : 38,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: dense ? 3 : 5),
              Text(
                '${today ? 'Today' : 'Selected day'} · $dateLabel',
                style: TextStyle(
                  color: _DiaryColors.secondary,
                  fontSize: dense ? 14 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Choose diary date',
          child: Material(
            color: _DiaryColors.sage,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onSelectDate,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: dense ? 44 : 52,
                height: dense ? 44 : 52,
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: _DiaryColors.forest,
                  size: 23,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailySummary extends StatelessWidget {
  const _DailySummary({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.compact,
    required this.dense,
  });

  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(dense ? 12 : compact ? 15 : 20),
      decoration: BoxDecoration(
        color: _DiaryColors.deepGreen,
        borderRadius: BorderRadius.circular(dense ? 21 : 26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SummaryIcon(
                icon: Icons.eco_rounded,
                color: const Color(0xFFB9E9C0),
                dense: dense,
              ),
              SizedBox(width: dense ? 8 : 11),
              Expanded(
                child: Text(
                  'Calories consumed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: dense ? 13 : 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SummaryIcon(
                icon: Icons.bar_chart_rounded,
                color: Colors.white,
                dense: dense,
              ),
            ],
          ),
          SizedBox(height: dense ? 1 : 4),
          Text(
            calories == null ? '— kcal' : '${calories!.round()} kcal',
            style: TextStyle(
              color: Colors.white,
              fontSize: dense ? 36 : compact ? 40 : 48,
              height: 1.02,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: dense ? 9 : 13),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.17)),
          SizedBox(height: dense ? 8 : 12),
          Row(
            children: [
              _MacroSummary(
                label: 'Protein',
                grams: protein,
                icon: Icons.eco_outlined,
                iconColor: const Color(0xFFB9E9C0),
                dense: dense,
              ),
              _MacroDivider(dense: dense),
              _MacroSummary(
                label: 'Carbs',
                grams: carbs,
                icon: Icons.grain_rounded,
                iconColor: const Color(0xFFFFD95E),
                dense: dense,
              ),
              _MacroDivider(dense: dense),
              _MacroSummary(
                label: 'Fat',
                grams: fat,
                icon: Icons.water_drop_rounded,
                iconColor: const Color(0xFFFFB184),
                dense: dense,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryIcon extends StatelessWidget {
  const _SummaryIcon({
    required this.icon,
    required this.color,
    required this.dense,
  });

  final IconData icon;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 30.0 : 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: dense ? 17 : 21),
    );
  }
}

class _MacroSummary extends StatelessWidget {
  const _MacroSummary({
    required this.label,
    required this.grams,
    required this.icon,
    required this.iconColor,
    required this.dense,
  });

  final String label;
  final double? grams;
  final IconData icon;
  final Color iconColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: dense ? 30 : 36,
            height: dense ? 30 : 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: dense ? 17 : 20),
          ),
          SizedBox(width: dense ? 6 : 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grams == null ? '— g' : '${grams!.round()} g',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: dense ? 14 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: dense ? 11 : 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroDivider extends StatelessWidget {
  const _MacroDivider({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: dense ? 29 : 35,
      margin: EdgeInsets.symmetric(horizontal: dense ? 5 : 8),
      color: Colors.white.withValues(alpha: 0.16),
    );
  }
}

class _AddMealButton extends StatelessWidget {
  const _AddMealButton({
    required this.compact,
    required this.onPressed,
  });

  final bool compact;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 23),
      label: const Text('Add meal'),
      style: FilledButton.styleFrom(
        backgroundColor: _DiaryColors.forest,
        foregroundColor: Colors.white,
        minimumSize: Size.fromHeight(compact ? 46 : 56),
        textStyle: TextStyle(
          fontSize: compact ? 15 : 17,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 18 : 24),
        ),
      ),
    );
  }
}

class _MealSectionCard extends StatelessWidget {
  const _MealSectionCard({
    required this.type,
    required this.meals,
    required this.calories,
    required this.compact,
    required this.dense,
    required this.onAddMeal,
  });

  final _MealType type;
  final List<MealScanResult> meals;
  final double? calories;
  final bool compact;
  final bool dense;
  final Future<void> Function(String?) onAddMeal;

  @override
  Widget build(BuildContext context) {
    final empty = meals.isEmpty;
    return Container(
      padding: EdgeInsets.all(dense ? 8 : compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(dense ? 18 : 23),
        border: Border.all(color: _DiaryColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F2018),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onAddMeal(type.key),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: dense ? 1 : 3),
              child: Row(
                children: [
                  Container(
                    width: dense ? 30 : compact ? 34 : 42,
                    height: dense ? 30 : compact ? 34 : 42,
                    decoration: BoxDecoration(
                      color: type.tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type.icon,
                      color: type.accent,
                      size: dense ? 17 : compact ? 20 : 24,
                    ),
                  ),
                  SizedBox(width: dense ? 8 : 11),
                  Expanded(
                    child: Text(
                      type.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: _DiaryColors.ink,
                        fontSize: dense ? 16 : compact ? 17 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    calories == null ? '— kcal' : '${calories!.round()} kcal',
                    style: TextStyle(
                      color: _DiaryColors.secondary,
                      fontSize: dense ? 12 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _DiaryColors.secondary,
                    size: dense ? 19 : 22,
                  ),
                ],
              ),
            ),
          ),
          if (empty) ...[
            SizedBox(height: dense ? 5 : 8),
            Material(
              color: const Color(0xFFF4F6F1),
              borderRadius: BorderRadius.circular(dense ? 13 : 17),
              child: InkWell(
                onTap: () => onAddMeal(type.key),
                borderRadius: BorderRadius.circular(dense ? 13 : 17),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 8 : 11,
                    vertical: dense ? 5 : 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        color: _DiaryColors.forest,
                        size: dense ? 23 : 26,
                      ),
                      SizedBox(width: dense ? 7 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              type.suggestion,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _DiaryColors.ink,
                                fontSize: dense ? 12 : compact ? 13 : 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!dense) ...[
                              const SizedBox(height: 1),
                              Text(
                                type.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _DiaryColors.secondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: _DiaryColors.secondary,
                        size: dense ? 19 : 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            for (final meal in meals) _MealCard(meal: meal, compact: compact),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onAddMeal(type.key),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Add ${type.label.toLowerCase()}'),
                style: TextButton.styleFrom(
                  foregroundColor: _DiaryColors.forest,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealType {
  const _MealType({
    required this.key,
    required this.label,
    required this.suggestion,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.accent,
  });

  final String key;
  final String label;
  final String suggestion;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color accent;
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.compact});

  final MealScanResult meal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final calories = _number(meal.nutritionTotals['energy_kcal']);
    final time = TimeOfDay.fromDateTime(meal.createdAt.toLocal());
    final foods = meal.components
        .map((item) => item['food_name'])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(
            Icons.restaurant_menu_rounded,
            color: _DiaryColors.forest,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              foods.isEmpty ? meal.mealName : '${meal.mealName} · $foods',
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _DiaryColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            calories == null ? time.format(context) : '${calories.round()} kcal',
            style: const TextStyle(
              color: _DiaryColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryColors {
  static const forest = Color(0xFF075B45);
  static const deepGreen = Color(0xFF064A37);
  static const ink = Color(0xFF111820);
  static const secondary = Color(0xFF68727A);
  static const sage = Color(0xFFE7F0E6);
  static const border = Color(0xFFE9ECE5);
}

double? _number(Object? value) =>
    value == null ? null : double.tryParse(value.toString());
