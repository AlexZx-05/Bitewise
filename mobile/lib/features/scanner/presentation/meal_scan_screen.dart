import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';
import '../data/meal_scan_repository.dart';
import 'alternative_product_card.dart';

class MealScanScreen extends ConsumerStatefulWidget {
  const MealScanScreen({this.initialMealType = 'lunch', super.key});

  final String initialMealType;

  @override
  ConsumerState<MealScanScreen> createState() => _MealScanScreenState();
}

class _MealScanScreenState extends ConsumerState<MealScanScreen> {
  final _picker = ImagePicker();
  final _mealName = TextEditingController();
  final List<_MealComponentDraft> _components = [];
  XFile? _photo;
  MealScanResult? _result;
  String _mealType = 'lunch';
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMealType;
  }

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

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (photo != null && mounted) {
        _clearComponents();
        setState(() {
          _photo = photo;
          _mealName.clear();
          _message = null;
          _messageIsError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        final sourceLabel = source == ImageSource.camera ? 'camera' : 'gallery';
        _showMessage(
          'Could not open the $sourceLabel. Check its permission and try again. ($error)',
          isError: true,
        );
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
      _messageIsError = false;
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
        _messageIsError = false;
      });
    } on FoodScanApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
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
    if (component.searching) {
      return;
    }
    if (searchTerm.length < 2) {
      _showMessage(
        'Enter at least two characters for the food name before searching USDA.',
        item: component,
        isError: true,
      );
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
        _showMessage(error.message, isError: true);
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
    if (_mealName.text.trim().isEmpty) {
      _showMessage('Add a meal name before saving.', isError: true);
      return;
    }
    if (_components.isEmpty) {
      _showMessage('Add at least one food item before saving.', isError: true);
      return;
    }
    for (var index = 0; index < _components.length; index++) {
      final item = _components[index];
      final pieces = double.tryParse(item.pieces.text.trim());
      final gramsPerPiece = double.tryParse(item.gramsPerPiece.text.trim());
      if (item.foodName.text.trim().isEmpty) {
        _showMessage(
          'Enter a name for food item ${index + 1}.',
          item: item,
          isError: true,
        );
        return;
      }
      final portion = double.tryParse(item.portionG.text.trim());
      if (portion == null || portion <= 0) {
        _showMessage(
          'Enter a valid portion in grams for ${item.foodName.text.trim()}.',
          item: item,
          isError: true,
        );
        return;
      }
      if (item.cookingMethod.text.trim().isEmpty) {
        _showMessage(
          'Confirm the cooking method for ${item.foodName.text.trim()}.',
          item: item,
          isError: true,
        );
        return;
      }
      if ((item.pieces.text.trim().isNotEmpty ||
              item.gramsPerPiece.text.trim().isNotEmpty) &&
          (pieces == null ||
              gramsPerPiece == null ||
              pieces <= 0 ||
              gramsPerPiece <= 0 ||
              (pieces * gramsPerPiece - portion).abs() > 0.1)) {
        _showMessage(
          'For ${item.foodName.text.trim()}, enter both pieces and grams per piece. Their total must match the portion in grams.',
          item: item,
          isError: true,
        );
        return;
      }
      if (item.selectedFood == null) {
        _showMessage(
          'Choose a nutrition result for food item ${index + 1}. Tap “Find nutrition info” and select the closest match.',
          item: item,
          isError: true,
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _message = 'Calculating from selected USDA food records…';
      _messageIsError = false;
    });
    try {
      final result = await ref.read(mealScanRepositoryProvider).confirmMeal({
        'meal_name': _mealName.text.trim(),
        'meal_type': _mealType,
        'components': _components
            .map(
              (item) => {
                'fdc_id': item.selectedFood!.fdcId,
                'food_name': item.foodName.text.trim(),
                'portion_g': double.parse(item.portionG.text.trim()),
                if (item.pieces.text.trim().isNotEmpty)
                  'portion_pieces': double.parse(item.pieces.text.trim()),
                if (item.gramsPerPiece.text.trim().isNotEmpty)
                  'grams_per_piece': double.parse(
                    item.gramsPerPiece.text.trim(),
                  ),
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
        ref.invalidate(mealDiaryProvider(todayMealDiaryKey()));
        setState(() => _result = result);
      }
    } on FoodScanApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(
    String message, {
    _MealComponentDraft? item,
    bool isError = false,
  }) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
    if (item != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final itemContext = item.cardKey.currentContext;
        if (itemContext != null) {
          Scrollable.ensureVisible(
            itemContext,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.12,
          );
        }
      });
    }
  }

  void _updatePieceWeight(_MealComponentDraft item) {
    final pieces = double.tryParse(item.pieces.text.trim());
    final gramsPerPiece = double.tryParse(item.gramsPerPiece.text.trim());
    if (pieces != null &&
        gramsPerPiece != null &&
        pieces > 0 &&
        gramsPerPiece > 0) {
      setState(
        () => item.portionG.text = (pieces * gramsPerPiece).toStringAsFixed(1),
      );
    }
  }

  void _reset() {
    _clearComponents();
    setState(() {
      _result = null;
      _photo = null;
      _mealName.clear();
      _message = null;
      _messageIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
    final matchedCount = _components
        .where((component) => component.selectedFood != null)
        .length;
    final shortScreen = MediaQuery.sizeOf(context).height < 760;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = shortScreen || constraints.maxWidth < 360;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: compact ? 0.16 : 0.24,
                    child: Image.asset(
                      'assets/images/food__welcome.png',
                      width: double.infinity,
                      height: constraints.maxHeight * (compact ? 0.34 : 0.43),
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 22,
                compact ? 10 : 18,
                compact ? 18 : 22,
                compact ? 20 : 28,
              ),
              children: [
                Text(
                  'PHOTO  →  CONFIRM  →  NUTRITION ESTIMATE',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF075B46),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: compact ? 10 : 16),
                Text(
                  'Capture your\nhome-cooked meal',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF063F32),
                    fontSize: compact ? 29 : 34,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                const Text(
                  'Choose a meal type and photo. Groq suggests visible foods; '
                  'review every item and portion before nutrition is calculated '
                  'from USDA records. Food photos are not saved.',
                  style: TextStyle(
                    color: Color(0xFF69736F),
                    fontSize: 14,
                    height: 1.42,
                  ),
                ),
                SizedBox(height: compact ? 15 : 21),
                Text(
                  'MEAL TYPE',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF52625A),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final type in const {
                      'breakfast': ('Breakfast', Icons.wb_sunny_outlined),
                      'lunch': ('Lunch', Icons.restaurant_outlined),
                      'dinner': ('Dinner', Icons.dark_mode_outlined),
                      'snack': ('Snack', Icons.apple_outlined),
                    }.entries)
                      _MealTypePill(
                        label: type.value.$1,
                        icon: type.value.$2,
                        selected: _mealType == type.key,
                        compact: compact,
                        onTap: _busy
                            ? null
                            : () => setState(() => _mealType = type.key),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 15 : 21),
                Row(
                  children: [
                    Expanded(
                      child: _MealPhotoActionCard(
                        title: 'Take photo',
                        description: 'Use your camera to capture your meal',
                        icon: Icons.camera_alt_outlined,
                        background: const Color(0xFFEAF2E9),
                        compact: compact,
                        onTap: _busy
                            ? null
                            : () => _pickPhoto(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MealPhotoActionCard(
                        title: 'Choose photo',
                        description: 'Select from your gallery',
                        icon: Icons.photo_library_outlined,
                        background: const Color(0xFFFFF8EC),
                        compact: compact,
                        onTap: _busy
                            ? null
                            : () => _pickPhoto(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                if (_photo case final photo?) ...[
                  const SizedBox(height: 14),
                  FutureBuilder(
                    future: photo.readAsBytes(),
                    builder: (context, snapshot) => snapshot.hasData
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              snapshot.data!,
                              height: compact ? 150 : 220,
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
                if (_components.isEmpty)
                  if (_message case final message?) ...[
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: TextStyle(
                        color: _messageIsError
                            ? Theme.of(context).colorScheme.error
                            : const Color(0xFF52625A),
                      ),
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
                  Text(
                    'Quick sizes are starting estimates. You can edit grams or enter pieces with grams per piece.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.sage,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.fact_check_outlined,
                          color: AppTheme.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'We look up nutrition for each food you confirm. Choose one matching result for every item ($matchedCount of ${_components.length} matched).',
                            style: const TextStyle(
                              color: AppTheme.green,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < _components.length; index++) ...[
                    const SizedBox(height: 14),
                    _componentEditor(_components[index], index),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _components.length >= 10
                        ? null
                        : () => setState(
                            () => _components.add(_MealComponentDraft()),
                          ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add a food item'),
                  ),
                  if (_message case final message? when message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _busy
                            ? AppTheme.sage
                            : _messageIsError
                            ? Theme.of(context).colorScheme.errorContainer
                            : AppTheme.sage,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_busy)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              _messageIsError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: _messageIsError
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer
                                  : AppTheme.green,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message),
                                if (_messageIsError && !_busy) ...[
                                  const SizedBox(height: 6),
                                  TextButton(
                                    onPressed: _analyzeMeal,
                                    style: TextButton.styleFrom(
                                      foregroundColor: _messageIsError
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onErrorContainer
                                          : AppTheme.green,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 36),
                                      alignment: Alignment.centerLeft,
                                    ),
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    label: Text(
                      matchedCount == _components.length
                          ? 'Calculate & save meal'
                          : 'Find nutrition info ($matchedCount of ${_components.length})',
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _componentEditor(_MealComponentDraft item, int index) {
    return Card(
      key: item.cardKey,
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
              onChanged: (_) {
                item.pieces.clear();
                item.gramsPerPiece.clear();
              },
              decoration: const InputDecoration(
                labelText: 'Confirmed portion (g)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Small · 100 g'),
                  onPressed: () => setState(() {
                    item.portionG.text = '100';
                    item.pieces.clear();
                    item.gramsPerPiece.clear();
                  }),
                ),
                ActionChip(
                  label: const Text('Medium · 200 g'),
                  onPressed: () => setState(() {
                    item.portionG.text = '200';
                    item.pieces.clear();
                    item.gramsPerPiece.clear();
                  }),
                ),
                ActionChip(
                  label: const Text('Large · 300 g'),
                  onPressed: () => setState(() {
                    item.portionG.text = '300';
                    item.pieces.clear();
                    item.gramsPerPiece.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.pieces,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _updatePieceWeight(item),
                    decoration: const InputDecoration(
                      labelText: 'Pieces (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: item.gramsPerPiece,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _updatePieceWeight(item),
                    decoration: const InputDecoration(
                      labelText: 'g per piece',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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
                    ? 'Finding nutrition…'
                    : item.selectedFood == null
                    ? 'Find nutrition info'
                    : 'Find a different match',
              ),
            ),
            if (item.selectedFood == null && item.foods.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Choose a nutrition result for this food to continue.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (item.foods.isNotEmpty)
              DropdownButtonFormField<UsdaFood>(
                initialValue: item.selectedFood,
                isExpanded: true,
                hint: const Text('Choose the closest food'),
                decoration: const InputDecoration(
                  labelText: 'Which one looks closest?',
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
                onChanged: (food) => setState(() {
                  item.selectedFood = food;
                  _message = null;
                }),
              ),
            if (item.selectedFood case final selected?) ...[
              const SizedBox(height: 6),
              Text(
                'Nutrition will use: ${selected.description}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (item.foods.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Pick the closest match. The serving and preparation should look like your food.',
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
                        labelText: 'Try a shorter food name',
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
                      child: const Text('Try this name'),
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
        const SizedBox(height: 4),
        Text(
          result.mealType[0].toUpperCase() + result.mealType.substring(1),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.green,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text('Confirmed items', style: Theme.of(context).textTheme.titleMedium),
        for (final item in result.components) _componentResultCard(item),
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
        Text(
          'A healthier option for your goal',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Card(
          color: AppTheme.sage,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: AppTheme.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.goalAlternative,
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (result.alternativeProduct case final product?) ...[
          const SizedBox(height: 8),
          Text(
            'Product to compare',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          AlternativeProductCard(product: product),
        ] else if (result.alternativeProductNotice case final notice?) ...[
          const SizedBox(height: 8),
          Text(notice, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Text(
          'Suggestion only. The nutrition estimate above is based on your confirmed foods and portions; this alternative is not nutritionally verified.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Nutrition is an estimate based on the specific USDA records and portions you confirmed. Recipes, brands, oil, and salt can make the real meal different.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.pop(true),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Saved to diary · Done'),
        ),
        TextButton(onPressed: _reset, child: const Text('Add another meal')),
      ],
    );
  }

  Widget _componentResultCard(Map<String, dynamic> item) {
    final nutrition =
        item['nutrition'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final pieceCount = item['portion_pieces'];
    final pieceLabel = pieceCount == null ? '' : ' · $pieceCount pieces';
    const componentNutrients = {
      'energy_kcal': 'kcal',
      'protein_g': 'g protein',
      'carbohydrates_g': 'g carbs',
      'total_fat_g': 'g fat',
    };
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item['food_name']} · ${item['portion_g']} g$pieceLabel',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'USDA match: ${item['data_source']}\n'
              'Ingredients: ${(item['ingredients'] as List).join(', ')} · '
              '${item['cooking_method']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final entry in componentNutrients.entries)
                  if (nutrition[entry.key] != null)
                    Chip(
                      label: Text('${nutrition[entry.key]} ${entry.value}'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MealTypePill extends StatelessWidget {
  const _MealTypePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF075B46);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? const Color(0xFF075B46) : const Color(0xFFFAFBF8),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 13,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected
                    ? const Color(0xFF075B46)
                    : const Color(0xFFD5E1D7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.check_rounded, size: 15),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MealPhotoActionCard extends StatelessWidget {
  const _MealPhotoActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.background,
    required this.compact,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color background;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $description',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: compact ? 142 : 164,
            padding: EdgeInsets.all(compact ? 11 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E9E2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A17251F),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: compact ? 38 : 44,
                      height: compact ? 38 : 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDDEBE0),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFF075B46),
                        size: compact ? 21 : 24,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF075B46),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF14251F),
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF69736F),
                    fontSize: compact ? 11 : 12,
                    height: 1.3,
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

class _MealComponentDraft {
  _MealComponentDraft({
    String foodName = '',
    String portionG = '',
    String ingredients = '',
    String cookingMethod = '',
    String alternativeSearch = '',
    String pieces = '',
    String gramsPerPiece = '',
  }) : foodName = TextEditingController(text: foodName),
       portionG = TextEditingController(text: portionG),
       pieces = TextEditingController(text: pieces),
       gramsPerPiece = TextEditingController(text: gramsPerPiece),
       ingredients = TextEditingController(text: ingredients),
       cookingMethod = TextEditingController(text: cookingMethod),
       alternativeSearch = TextEditingController(text: alternativeSearch);

  final TextEditingController foodName;
  final TextEditingController portionG;
  final TextEditingController pieces;
  final TextEditingController gramsPerPiece;
  final TextEditingController ingredients;
  final TextEditingController cookingMethod;
  final TextEditingController alternativeSearch;
  final GlobalKey cardKey = GlobalKey();
  List<UsdaFood> foods = [];
  UsdaFood? selectedFood;
  String? searchError;
  bool noMatches = false;
  bool searching = false;

  void dispose() {
    foodName.dispose();
    portionG.dispose();
    pieces.dispose();
    gramsPerPiece.dispose();
    ingredients.dispose();
    cookingMethod.dispose();
    alternativeSearch.dispose();
  }
}
