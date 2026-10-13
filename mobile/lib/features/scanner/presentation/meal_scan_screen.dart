import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';
import '../data/meal_scan_repository.dart';

class MealScanScreen extends ConsumerStatefulWidget {
  const MealScanScreen({super.key});

  @override
  ConsumerState<MealScanScreen> createState() => _MealScanScreenState();
}

class _MealScanScreenState extends ConsumerState<MealScanScreen> {
  final _picker = ImagePicker();
  final _mealName = TextEditingController();
  final List<_MealComponentDraft> _components = [];
  XFile? _photo;
  MealScanResult? _result;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _mealName.dispose();
    _clearComponents();
    super.dispose();
  }

  void _clearComponents() {
    for (final component in _components) {
      component.dispose();
    }
    _components.clear();
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo != null && mounted) {
        setState(() {
          _photo = photo;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not open photo picker: $error');
      }
    }
  }

  Future<void> _identifyMeal() async {
    final photo = _photo;
    if (photo == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Identifying visible meal components…';
    });
    try {
      final extracted = await ref
          .read(mealScanRepositoryProvider)
          .extractMeal(
            bytes: await photo.readAsBytes(),
            name: photo.name,
            mimeType: photo.mimeType ?? 'image/jpeg',
          );
      if (!mounted) {
        return;
      }
      _mealName.text = extracted['meal_name']?.toString() ?? '';
      _clearComponents();
      final components = extracted['components'];
      if (components is List) {
        for (final value in components.whereType<Map<String, dynamic>>()) {
          final ingredients = value['possible_ingredients'];
          _components.add(
            _MealComponentDraft(
              foodName: value['food_name']?.toString() ?? '',
              portionG: value['estimated_portion_g']?.toString() ?? '',
              ingredients: ingredients is List
                  ? ingredients.map((item) => item.toString()).join(', ')
                  : '',
              cookingMethod:
                  value['suggested_cooking_method']?.toString() ?? '',
            ),
          );
        }
      }
      setState(() {
        _message =
            'These are AI suggestions, not verified facts. Confirm the dish, ingredients, cooking method, and portion before nutrition lookup.';
      });
    } on FoodScanApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _searchFood(
    _MealComponentDraft component, {
    String? query,
  }) async {
    final searchTerm = (query ?? component.foodName.text).trim();
    if (searchTerm.length < 2 || component.searching) {
      return;
    }
    setState(() {
      component.searching = true;
      component.searchError = null;
      component.noMatches = false;
      component.foods = [];
      component.selectedFood = null;
    });
    try {
      final foods = await ref
          .read(mealScanRepositoryProvider)
          .searchFoods(searchTerm);
      if (!mounted) {
        return;
      }
      setState(() {
        component.foods = foods;
        if (foods.isEmpty) {
          component.noMatches = true;
          component.searchError =
              'No direct USDA match for "$searchTerm". Your meal item stays unchanged.';
        }
      });
    } on FoodScanApiException catch (error) {
      if (mounted) {
        setState(() {
          component.searchError = error.message;
          component.noMatches = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => component.searching = false);
      }
    }
  }

  void _clearFoodMatch(_MealComponentDraft component) {
    if (component.foods.isEmpty &&
        component.selectedFood == null &&
        component.searchError == null) {
      return;
    }
    setState(() {
      component.foods = [];
      component.selectedFood = null;
      component.searchError = null;
      component.noMatches = false;
    });
  }

  Future<void> _analyzeMeal() async {
    if (_busy) {
      return;
    }
    if (_mealName.text.trim().isEmpty || _components.isEmpty) {
      setState(
        () => _message = 'Confirm the meal name and at least one food item.',
      );
      return;
    }
    for (final item in _components) {
      if (item.foodName.text.trim().isEmpty ||
          double.tryParse(item.portionG.text.trim()) == null ||
          double.parse(item.portionG.text.trim()) <= 0 ||
          item.selectedFood == null ||
          item.cookingMethod.text.trim().isEmpty) {
        setState(
          () => _message =
              'For each item, confirm its name, portion in grams, cooking method, and USDA food match.',
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _message = 'Calculating from selected USDA food records…';
    });
    try {
      final result = await ref.read(mealScanRepositoryProvider).confirmMeal({
        'meal_name': _mealName.text.trim(),
        'components': _components
            .map(
              (item) => {
                'fdc_id': item.selectedFood!.fdcId,
                'food_name': item.foodName.text.trim(),
                'portion_g': double.parse(item.portionG.text.trim()),
                'ingredients': item.ingredients.text
                    .split(RegExp(r'[\n,;]'))
                    .map((part) => part.trim())
                    .where((part) => part.isNotEmpty)
                    .toList(),
                'cooking_method': item.cookingMethod.text.trim(),
              },
            )
            .toList(),
      });
      if (mounted) {
        setState(() => _result = result);
      }
    } on FoodScanApiException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _reset() {
    _clearComponents();
    setState(() {
      _result = null;
      _photo = null;
      _mealName.clear();
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        title: Text(result == null ? 'Home-cooked meal' : 'Meal analysis'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: result == null ? _buildFlow() : _buildResults(result),
          ),
        ),
      ),
    );
  }

  Widget _buildFlow() {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          'Photo → confirm → nutrition estimate',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The meal photo is sent to FoodScan and Groq for suggested dish identification. Confirm ingredients and portions; the image is not saved by FoodScan.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickPhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_photo == null ? 'Choose meal photo' : 'Change photo'),
        ),
        if (_photo case final photo?) ...[
          const SizedBox(height: 10),
          FutureBuilder(
            future: photo.readAsBytes(),
            builder: (context, snapshot) => snapshot.hasData
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      snapshot.data!,
                      height: 220,
                      fit: BoxFit.cover,
                    ),
                  )
                : const LinearProgressIndicator(),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _identifyMeal,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Identify meal with AI'),
          ),
        ],
        if (_components.isNotEmpty) ...[
          const SizedBox(height: 18),
          TextField(
            controller: _mealName,
            decoration: const InputDecoration(
              labelText: 'Meal name — confirm or edit',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Edit every suggested item. Vision cannot reliably know hidden ingredients, oil, salt, or portion weight.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (var index = 0; index < _components.length; index++) ...[
            const SizedBox(height: 14),
            _componentEditor(_components[index], index),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _components.length >= 10
                ? null
                : () => setState(() => _components.add(_MealComponentDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Add a food item'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _analyzeMeal,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.analytics_outlined),
            label: const Text('Confirm and calculate nutrition'),
          ),
        ],
        if (_message case final message? when message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppTheme.green)),
        ],
      ],
    );
  }

  Widget _componentEditor(_MealComponentDraft item, int index) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Food item ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _components.length == 1
                      ? null
                      : () {
                          setState(() {
                            item.dispose();
                            _components.removeAt(index);
                          });
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: item.foodName,
              onChanged: (_) => _clearFoodMatch(item),
              decoration: const InputDecoration(
                labelText: 'Food name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.portionG,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Confirmed portion (g)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.ingredients,
              onChanged: (_) => _clearFoodMatch(item),
              decoration: const InputDecoration(
                labelText: 'Ingredients (confirm/edit)',
                hintText: 'e.g. rice, lentils, oil, spices',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.cookingMethod,
              onChanged: (_) => _clearFoodMatch(item),
              decoration: const InputDecoration(
                labelText: 'Cooking method (confirm/edit)',
                hintText: 'e.g. boiled, pan-fried, deep-fried',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: item.searching ? null : () => _searchFood(item),
              child: Text(
                item.searching
                    ? 'Searching USDA…'
                    : 'Find matching USDA nutrition data',
              ),
            ),
            if (item.foods.isNotEmpty)
              DropdownButtonFormField<UsdaFood>(
                initialValue: item.selectedFood,
                isExpanded: true,
                hint: const Text('Select a matching USDA record'),
                decoration: const InputDecoration(
                  labelText: 'Confirm nutrition record',
                  border: OutlineInputBorder(),
                ),
                items: item.foods
                    .map(
                      (food) => DropdownMenuItem(
                        value: food,
                        child: Text(
                          '${food.description} (${food.dataType ?? 'USDA'})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (food) => setState(() => item.selectedFood = food),
              ),
            if (item.foods.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Choose the record that best matches this food and preparation. Nutrition is calculated from that USDA record.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (item.searchError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      error,
                      style: TextStyle(
                        color: item.noMatches
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: item.alternativeSearch,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (query) => _searchFood(item, query: query),
                      decoration: const InputDecoration(
                        labelText: 'Search USDA with a simpler food name',
                        hintText: 'For example: cooked lentils',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: item.searching
                          ? null
                          : () => _searchFood(
                              item,
                              query: item.alternativeSearch.text,
                            ),
                      child: const Text('Search this name'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(MealScanResult result) {
    const nutrientLabels = {
      'energy_kcal': 'Energy (kcal)',
      'protein_g': 'Protein (g)',
      'carbohydrates_g': 'Carbohydrates (g)',
      'total_fat_g': 'Total fat (g)',
      'sodium_mg': 'Sodium (mg)',
    };
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          result.mealName,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Text('Confirmed items', style: Theme.of(context).textTheme.titleMedium),
        for (final item in result.components)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${item['food_name']} · ${item['portion_g']} g'),
            subtitle: Text(
              'USDA match: ${item['data_source']}\n'
              'Ingredients: ${(item['ingredients'] as List).join(', ')} · '
              '${item['cooking_method']}',
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Estimated meal nutrition',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Card(
          child: Column(
            children: [
              for (final entry in nutrientLabels.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: Text(
                    result.nutritionTotals[entry.key]?.toString() ??
                        'Unavailable in selected records',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(result.goalExplanation),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(result.alternativeGuidance),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Nutrition is an estimate based on the specific USDA records and portions you confirmed. Recipes, brands, oil, and salt can make the real meal different.',
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: _reset, child: const Text('Scan another meal')),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Back to home'),
        ),
      ],
    );
  }
}

class _MealComponentDraft {
  _MealComponentDraft({
    String foodName = '',
    String portionG = '',
    String ingredients = '',
    String cookingMethod = '',
    String alternativeSearch = '',
  }) : foodName = TextEditingController(text: foodName),
       portionG = TextEditingController(text: portionG),
       ingredients = TextEditingController(text: ingredients),
       cookingMethod = TextEditingController(text: cookingMethod),
       alternativeSearch = TextEditingController(text: alternativeSearch);

  final TextEditingController foodName;
  final TextEditingController portionG;
  final TextEditingController ingredients;
  final TextEditingController cookingMethod;
  final TextEditingController alternativeSearch;
  List<UsdaFood> foods = [];
  UsdaFood? selectedFood;
  String? searchError;
  bool noMatches = false;
  bool searching = false;

  void dispose() {
    foodName.dispose();
    portionG.dispose();
    ingredients.dispose();
    cookingMethod.dispose();
    alternativeSearch.dispose();
  }
}
