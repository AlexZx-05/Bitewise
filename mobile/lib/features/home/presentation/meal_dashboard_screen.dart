import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../scanner/data/meal_scan_repository.dart';

class MealDashboardScreen extends ConsumerWidget {
  const MealDashboardScreen({required this.onAddMeal, super.key});

  final ValueChanged<String?> onAddMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diary = ref.watch(mealDiaryProvider(todayMealDiaryKey()));
    return diary.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 38),
              const SizedBox(height: 12),
              Text(
                'Could not load today’s meals.\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    ref.invalidate(mealDiaryProvider(todayMealDiaryKey())),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (meals) => _MealDiaryContent(
        meals: meals,
        onAddMeal: onAddMeal,
        onRefresh: () async =>
            ref.invalidate(mealDiaryProvider(todayMealDiaryKey())),
      ),
    );
  }
}

class _MealDiaryContent extends StatelessWidget {
  const _MealDiaryContent({
    required this.meals,
    required this.onAddMeal,
    required this.onRefresh,
  });

  final List<MealScanResult> meals;
  final ValueChanged<String?> onAddMeal;
  final Future<void> Function() onRefresh;

  static const _mealTypes = {
    'breakfast': ('Breakfast', Icons.wb_twilight_outlined),
    'lunch': ('Lunch', Icons.wb_sunny_outlined),
    'dinner': ('Dinner', Icons.nights_stay_outlined),
    'snack': ('Snacks', Icons.cookie_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final calories = _total('energy_kcal');
    final protein = _total('protein_g');
    final carbs = _total('carbohydrates_g');
    final fat = _total('total_fat_g');

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
        children: [
          Text(
            'Your meals',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppTheme.charcoal,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Today · ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.charcoal.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 18),
          _DailySummary(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => onAddMeal(null),
            icon: const Icon(Icons.add),
            label: const Text('Add meal'),
          ),
          const SizedBox(height: 26),
          for (final type in _mealTypes.entries) ...[
            Row(
              children: [
                Icon(type.value.$2, color: AppTheme.green),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    type.value.$1,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.charcoal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${meals.where((meal) => meal.mealType == type.key).length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...meals
                .where((meal) => meal.mealType == type.key)
                .map((meal) => _MealCard(meal: meal)),
            if (!meals.any((meal) => meal.mealType == type.key))
              _EmptyMealType(
                label: type.value.$1.toLowerCase(),
                mealType: type.key,
                onAddMeal: onAddMeal,
              ),
            const SizedBox(height: 20),
          ],
          const Text(
            'Nutrition values are estimates based on the USDA foods and portions you confirmed.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
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
}

class _DailySummary extends StatelessWidget {
  const _DailySummary({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;

  @override
  Widget build(BuildContext context) {
    final caloriesValue = calories;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.green,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calories consumed',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            caloriesValue == null ? '— kcal' : '${caloriesValue.round()} kcal',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MacroValue(label: 'Protein', grams: protein),
              _MacroValue(label: 'Carbs', grams: carbs),
              _MacroValue(label: 'Fat', grams: fat),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroValue extends StatelessWidget {
  const _MacroValue({required this.label, required this.grams});

  final String label;
  final double? grams;

  @override
  Widget build(BuildContext context) {
    final gramsValue = grams;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gramsValue == null ? '— g' : '${gramsValue.round()} g',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});

  final MealScanResult meal;

  @override
  Widget build(BuildContext context) {
    final calories = _number(meal.nutritionTotals['energy_kcal']);
    final time = TimeOfDay.fromDateTime(meal.createdAt.toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    meal.mealName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (calories != null)
                  Text(
                    '${calories.round()} kcal',
                    style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${time.format(context)} · ${meal.components.map((item) => item['food_name']).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMealType extends StatelessWidget {
  const _EmptyMealType({
    required this.label,
    required this.mealType,
    required this.onAddMeal,
  });

  final String label;
  final String mealType;
  final ValueChanged<String?> onAddMeal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => onAddMeal(mealType),
        leading: const Icon(Icons.add_circle_outline, color: AppTheme.green),
        title: Text('Add your $label'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

double? _number(Object? value) =>
    value == null ? null : double.tryParse(value.toString());
