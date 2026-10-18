import 'package:flutter/foundation.dart';
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
  final _reviewRevision = ValueNotifier<int>(0);
  XFile? _photo;
  MealScanResult? _result;
  String _mealType = 'lunch';
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;
  bool _reviewStep = false;

  @override
  void initState() {
    super.initState();
    _mealType = widget.initialMealType;
  }

  @override
  void dispose() {
    _mealName.dispose();
    _reviewRevision.dispose();
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
        _busy = false;
        _message =
            'These are AI suggestions, not verified facts. Confirm the dish, ingredients, cooking method, and portion before nutrition lookup.';
        _messageIsError = false;
      });
      _reviewRevision.value++;
      await _openReviewPage(photo);
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
    _reviewRevision.value++;
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
      _reviewRevision.value++;
    } on FoodScanApiException catch (error) {
      if (mounted) {
        setState(() {
          component.searchError = error.message;
          component.noMatches = false;
        });
        _reviewRevision.value++;
        _showMessage(error.message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => component.searching = false);
        _reviewRevision.value++;
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
    _reviewRevision.value++;
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
    _reviewRevision.value++;
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
        Navigator.of(context).pop(result);
      }
    } on FoodScanApiException catch (error) {
      if (mounted) {
        _showMessage(error.message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reviewRevision.value++;
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
    _reviewRevision.value++;
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
      _reviewRevision.value++;
    }
  }

  void _setReviewState(VoidCallback update) {
    setState(update);
    _reviewRevision.value++;
  }

  Future<void> _chooseFoodMatch(_MealComponentDraft item) async {
    final searchController = TextEditingController();
    var query = '';
    try {
      final selected = await showModalBottomSheet<UsdaFood>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final media = MediaQuery.of(sheetContext);
          final availableHeight =
              media.size.height -
              media.viewInsets.bottom -
              media.padding.top -
              24;
          final height = availableHeight <= 0
              ? 0.0
              : media.size.height * 0.84 < availableHeight
              ? media.size.height * 0.84
              : availableHeight;
          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: height,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAF9F4),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    final normalizedQuery = query.trim().toLowerCase();
                    final matches = item.foods.where((food) {
                      return food.description.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          (food.dataType?.toLowerCase().contains(
                                normalizedQuery,
                              ) ??
                              false);
                    }).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC8D0CA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Choose nutrition match',
                                      style: TextStyle(
                                        color: Color(0xFF101820),
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'For ${item.foodName.text.trim()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF657078),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                tooltip: 'Close nutrition matches',
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                          child: TextField(
                            controller: searchController,
                            onChanged: (value) =>
                                setSheetState(() => query = value),
                            decoration: InputDecoration(
                              hintText: 'Search these matches',
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCDD7D2),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCDD7D2),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppTheme.green,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                          child: Text(
                            '${matches.length} ${matches.length == 1 ? 'match' : 'matches'} · choose the closest preparation',
                            style: const TextStyle(
                              color: Color(0xFF657078),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: matches.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.search_off_rounded,
                                          size: 32,
                                          color: Color(0xFF87928C),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          'No matching results',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Try a different search term.',
                                          style: TextStyle(
                                            color: Color(0xFF657078),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    0,
                                    12,
                                    20,
                                  ),
                                  itemCount: matches.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final food = matches[index];
                                    final isSelected =
                                        food.fdcId == item.selectedFood?.fdcId;
                                    return Material(
                                      color: isSelected
                                          ? const Color(0xFFEAF3EB)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () =>
                                            Navigator.pop(context, food),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      food.description,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF17231E,
                                                        ),
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      food.dataType ??
                                                          'USDA food record',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF657078,
                                                        ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(
                                                isSelected
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                          .chevron_right_rounded,
                                                color: isSelected
                                                    ? AppTheme.green
                                                    : const Color(0xFF87928C),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
      if (selected != null && mounted) {
        _setReviewState(() {
          item.selectedFood = selected;
          _message = null;
        });
      }
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _openReviewPage(XFile photo) async {
    final result = await Navigator.of(context).push<MealScanResult>(
      MaterialPageRoute(
        builder: (context) => _MealReviewScreen(
          mealName: _mealName,
          mealType: _mealType,
          photo: photo,
          components: _components,
          revision: _reviewRevision,
          componentBuilder: _componentEditor,
          onAddItem: () =>
              _setReviewState(() => _components.add(_MealComponentDraft())),
          onSubmit: _analyzeMeal,
          isBusy: () => _busy,
          message: () => _message,
          messageIsError: () => _messageIsError,
          matchedCount: () => _components
              .where((component) => component.selectedFood != null)
              .length,
          onChangePhoto: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _result = result);
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
          onPressed: () {
            if (_reviewStep && !_busy) {
              setState(() {
                _reviewStep = false;
                _message = null;
              });
            } else {
              context.pop();
            }
          },
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        title: Text(
          result != null
              ? 'Meal analysis'
              : _reviewStep
              ? 'Review your meal'
              : 'Home-cooked meal',
        ),
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
                child: Image.asset(
                  'assets/images/Meal_scanner.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
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
                  _reviewStep
                      ? 'STEP 2 OF 2  ·  REVIEW & CONFIRM'
                      : 'STEP 1 OF 2  ·  ADD A MEAL PHOTO',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF075B46),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: compact ? 10 : 16),
                Text(
                  _reviewStep
                      ? 'Review your\nmeal details'
                      : 'Capture your\nhome-cooked meal',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF063F32),
                    fontSize: compact ? 29 : 34,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  _reviewStep
                      ? 'Check the AI suggestions and confirm each food, '
                            'ingredient, cooking method, and portion before '
                            'we estimate nutrition.'
                      : 'Choose a meal type and photo. We’ll identify the '
                            'visible foods, then you can review every detail '
                            'before nutrition is estimated.',
                  style: const TextStyle(
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
                if (!_reviewStep) ...[
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
                ],
                if (_photo case final photo? when !_reviewStep) ...[
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
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _busy
                          ? 'Identifying your meal…'
                          : 'Identify meal with AI',
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Usually takes a few seconds',
                        style: TextStyle(
                          color: Color(0xFF69736F),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
                if (_photo case final photo? when _reviewStep) ...[
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    color: const Color(0xFFFDFCF8).withValues(alpha: 0.94),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFFE5E9E2)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        FutureBuilder(
                          future: photo.readAsBytes(),
                          builder: (context, snapshot) => snapshot.hasData
                              ? Image.memory(
                                  snapshot.data!,
                                  width: 104,
                                  height: 94,
                                  fit: BoxFit.cover,
                                )
                              : const SizedBox(
                                  width: 104,
                                  height: 94,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Meal photo',
                                style: TextStyle(
                                  color: Color(0xFF14251F),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'AI suggestions are ready to review',
                                style: TextStyle(
                                  color: Color(0xFF69736F),
                                  fontSize: 12,
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _reviewStep = false;
                                        _message = null;
                                      }),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                  alignment: Alignment.centerLeft,
                                ),
                                child: const Text('Change photo'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
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
                if (_reviewStep && _components.isEmpty) ...[
                  const SizedBox(height: 18),
                  Card(
                    color: const Color(0xFFFDFCF8).withValues(alpha: 0.94),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 34,
                            color: AppTheme.green,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No foods were identified',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Try a clearer photo with the whole meal visible.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _identifyMeal,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try identification again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_reviewStep && _components.isNotEmpty) ...[
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
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x14101820),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE8ECE8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Food item ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF101820),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _components.length == 1
                      ? null
                      : () {
                          _setReviewState(() {
                            item.dispose();
                            _components.removeAt(index);
                          });
                        },
                  tooltip: 'Remove food item',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFF657078),
                  ),
                ),
              ],
            ),
            TextField(
              controller: item.foodName,
              onChanged: (_) => _clearFoodMatch(item),
              decoration: _reviewInputDecoration(
                labelText: 'Food name',
                icon: Icons.eco_outlined,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.portionG,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                item.pieces.clear();
                item.gramsPerPiece.clear();
                _reviewRevision.value++;
              },
              decoration: _reviewInputDecoration(
                labelText: 'Confirmed portion (g)',
                hintText: 'Enter portion in grams',
                icon: Icons.monitor_weight_outlined,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final presets = [
                  (label: 'Small · 100 g', grams: '100'),
                  (label: 'Medium · 200 g', grams: '200'),
                  (label: 'Large · 300 g', grams: '300'),
                ];
                if (constraints.maxWidth < 320) {
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in presets)
                        _portionPreset(item, preset),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0; index < presets.length; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      Expanded(child: _portionPreset(item, presets[index])),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  TextField(
                    controller: item.pieces,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _updatePieceWeight(item),
                    decoration: _reviewInputDecoration(
                      labelText: 'Pieces',
                      hintText: 'Optional',
                      icon: Icons.widgets_outlined,
                    ),
                  ),
                  TextField(
                    controller: item.gramsPerPiece,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => _updatePieceWeight(item),
                    decoration: _reviewInputDecoration(
                      labelText: 'Weight per piece',
                      hintText: 'g / piece',
                      icon: Icons.scale_outlined,
                    ),
                  ),
                ];
                if (constraints.maxWidth < 320) {
                  return Column(
                    children: [
                      fields[0],
                      const SizedBox(height: 10),
                      fields[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 10),
                    Expanded(child: fields[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.ingredients,
              onChanged: (_) => _clearFoodMatch(item),
              minLines: 1,
              maxLines: 2,
              decoration: _reviewInputDecoration(
                labelText: 'Ingredients (confirm/edit)',
                hintText: 'Edit the ingredients identified in your meal',
                icon: Icons.eco_outlined,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.cookingMethod,
              onChanged: (_) => _clearFoodMatch(item),
              decoration: _reviewInputDecoration(
                labelText: 'Cooking method (confirm/edit)',
                hintText: 'e.g. steamed, roasted, or raw',
                icon: Icons.soup_kitchen_outlined,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: item.searching ? null : () => _searchFood(item),
              icon: item.searching
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.manage_search_rounded),
              label: Text(
                 item.searching
                    ? 'Finding nutrition…'
                    : item.selectedFood == null
                    ? 'Find nutrition info'
                    : 'Find a different match',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppTheme.green,
                side: const BorderSide(color: AppTheme.green, width: 1.4),
                shape: const StadiumBorder(),
              ),
            ),
            if (item.selectedFood == null && item.foods.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3EB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 19,
                        color: AppTheme.green,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Choose the best matching nutrition result to continue.',
                          style: TextStyle(
                            color: AppTheme.green,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (item.foods.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'USDA NUTRITION MATCH',
                style: TextStyle(
                  color: Color(0xFF52615A),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 7),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _chooseFoodMatch(item),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 66),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: item.selectedFood == null
                            ? const Color(0xFFCDD7D2)
                            : const Color(0xFF9DC7A7),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.selectedFood == null
                              ? Icons.search_rounded
                              : Icons.check_circle_rounded,
                          color: AppTheme.green,
                          size: 21,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.selectedFood == null
                                    ? 'Choose the closest match'
                                    : item.selectedFood!.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: item.selectedFood == null
                                      ? const Color(0xFF657078)
                                      : const Color(0xFF173D30),
                                  fontSize: 14,
                                  fontWeight: item.selectedFood == null
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              if (item.selectedFood?.dataType case final type?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    type,
                                    style: const TextStyle(
                                      color: Color(0xFF657078),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF657078),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (item.selectedFood != null) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3EB),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFD6E6D8)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.green,
                      size: 17,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: const Text(
                        'This USDA record will be used for the nutrition estimate.',
                        style: TextStyle(
                          color: AppTheme.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (item.foods.isNotEmpty) ...[
              const SizedBox(height: 8),
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

  Widget _portionPreset(
    _MealComponentDraft item,
    ({String label, String grams}) preset,
  ) {
    final selected = item.portionG.text.trim() == preset.grams;
    return ChoiceChip(
      label: Text(
        preset.label,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.green,
      backgroundColor: const Color(0xFFF4F6F2),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF34413C),
        fontWeight: FontWeight.w600,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      onSelected: (_) => _setReviewState(() {
        item.portionG.text = preset.grams;
        item.pieces.clear();
        item.gramsPerPiece.clear();
      }),
    );
  }

  InputDecoration _reviewInputDecoration({
    required String labelText,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppTheme.green, size: 21),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF9BAAA5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.green, width: 1.6),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _buildResults(MealScanResult result) {
    final goalLabel = ref.watch(profileProvider).asData?.value.goalLabel;
    final alternative = result.goalAlternative.trim();
    final suggestion = alternative.isEmpty
        ? 'No personalized suggestion is available for this meal yet. You can still use the confirmed nutrition estimate above.'
        : alternative;
    final mealTypeLabel = result.mealType.isEmpty
        ? 'Meal'
        : '${result.mealType[0].toUpperCase()}${result.mealType.substring(1)}';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
            children: [
              _MealAnalysisHero(
                mealName: result.mealName,
                mealType: mealTypeLabel,
                photo: _photo,
              ),
              const SizedBox(height: 20),
              _ResultSectionHeading(
                icon: Icons.restaurant_rounded,
                title: 'Confirmed items (${result.components.length})',
                subtitle:
                    'These items and portions were used to estimate nutrition.',
              ),
              const SizedBox(height: 10),
              for (final item in result.components) ...[
                _ConfirmedFoodCard(item: item),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              _EstimatedMealNutrition(
                totals: result.nutritionTotals,
                itemCount: result.components.length,
              ),
              const SizedBox(height: 10),
              _NutritionDisclaimerCard(totals: result.nutritionTotals),
              const SizedBox(height: 16),
              _HealthierSuggestionCard(
                goalLabel: goalLabel,
                suggestion: suggestion,
                explanation: result.goalExplanation,
              ),
              if (result.alternativeProduct case final product?) ...[
                const SizedBox(height: 14),
                const _ResultSectionHeading(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Product to compare',
                ),
                const SizedBox(height: 8),
                AlternativeProductCard(product: product),
              ],
              if (result.alternativeProductNotice case final notice?) ...[
                const SizedBox(height: 10),
                _ResultNoteRow(icon: Icons.info_outline_rounded, text: notice),
              ],
              const SizedBox(height: 16),
              _ImportantNotesSection(
                hasAlternativeProduct: result.alternativeProduct != null,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFAF9F4),
            border: Border(top: BorderSide(color: Color(0xFFE8ECE5))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.pop(true),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Saved to diary · Done'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF075B46),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add another meal'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF075B46),
                    side: const BorderSide(color: Color(0xFF075B46)),
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MealAnalysisHero extends StatelessWidget {
  const _MealAnalysisHero({
    required this.mealName,
    required this.mealType,
    required this.photo,
  });

  final String mealName;
  final String mealType;
  final XFile? photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 162),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1E8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imageWidth = constraints.maxWidth < 340 ? 88.0 : 112.0;
          final titleSize = constraints.maxWidth < 340 ? 19.0 : 22.0;
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mealName,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF14231F),
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1EEE4),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.restaurant_rounded,
                            size: 16,
                            color: Color(0xFF075B46),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            mealType,
                            style: const TextStyle(
                              color: Color(0xFF075B46),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (photo != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FutureBuilder(
                    future: photo!.readAsBytes(),
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(
                            snapshot.data!,
                            width: imageWidth,
                            height: 128,
                            fit: BoxFit.cover,
                          )
                        : SizedBox(
                            width: imageWidth,
                            height: 128,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ResultSectionHeading extends StatelessWidget {
  const _ResultSectionHeading({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFFE7F0E8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF075B46), size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF14231F),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle case final value?) ...[
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF69736F),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmedFoodCard extends StatelessWidget {
  const _ConfirmedFoodCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final nutrition =
        item['nutrition'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final ingredients = item['ingredients'] is List
        ? (item['ingredients'] as List)
              .map((value) => value.toString())
              .join(', ')
        : '';
    final cookingMethod = item['cooking_method']?.toString() ?? '';
    final dataSource = item['data_source']?.toString() ?? 'USDA food record';
    final pieceCount = item['portion_pieces'];
    final portion =
        '${item['portion_g'] ?? '—'} g'
        '${pieceCount == null ? '' : ' · $pieceCount pieces'}';
    final details = [
      if (ingredients.isNotEmpty) 'Ingredients: $ingredients',
      if (cookingMethod.isNotEmpty) 'Preparation: $cookingMethod',
    ];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE8ECE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0914231F),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3E9),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.rice_bowl_rounded,
                  color: Color(0xFF075B46),
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['food_name']?.toString() ?? 'Confirmed food',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF14231F),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      portion,
                      style: const TextStyle(
                        color: Color(0xFF52615A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'USDA match: $dataSource',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF69736F),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (details.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 12),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF075B46),
                    size: 21,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 4 : 2;
              final gap = 7.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              const nutrients = [
                (
                  key: 'energy_kcal',
                  label: 'Calories',
                  unit: 'kcal',
                  icon: Icons.local_fire_department_rounded,
                  color: Color(0xFFFF914D),
                  background: Color(0xFFFFF1E7),
                ),
                (
                  key: 'protein_g',
                  label: 'Protein',
                  unit: 'g',
                  icon: Icons.eco_rounded,
                  color: Color(0xFF24785B),
                  background: Color(0xFFEAF3E9),
                ),
                (
                  key: 'carbohydrates_g',
                  label: 'Carbs',
                  unit: 'g',
                  icon: Icons.grain_rounded,
                  color: Color(0xFFE0A52F),
                  background: Color(0xFFFFF6E3),
                ),
                (
                  key: 'total_fat_g',
                  label: 'Fat',
                  unit: 'g',
                  icon: Icons.water_drop_rounded,
                  color: Color(0xFFF07868),
                  background: Color(0xFFFFEFEC),
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: 7,
                children: [
                  for (final nutrient in nutrients)
                    SizedBox(
                      width: width,
                      child: _CompactNutrientValue(
                        label: nutrient.label,
                        value: _nutritionValue(nutrition[nutrient.key]),
                        unit: nutrient.unit,
                        icon: nutrient.icon,
                        color: nutrient.color,
                        background: nutrient.background,
                      ),
                    ),
                ],
              );
            },
          ),
          if (details.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                listTileTheme: const ListTileThemeData(
                  minVerticalPadding: 0,
                  contentPadding: EdgeInsets.zero,
                  horizontalTitleGap: 8,
                ),
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 3),
                visualDensity: VisualDensity.compact,
                minTileHeight: 38,
                title: const Text(
                  'Ingredients & preparation',
                  style: TextStyle(
                    color: Color(0xFF075B46),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF075B46),
                ),
                children: [
                  for (final detail in details)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          detail,
                          style: const TextStyle(
                            color: Color(0xFF69736F),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
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

class _CompactNutrientValue extends StatelessWidget {
  const _CompactNutrientValue({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$value $unit\n$label',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF26342E),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimatedMealNutrition extends StatelessWidget {
  const _EstimatedMealNutrition({
    required this.totals,
    required this.itemCount,
  });

  final Map<String, dynamic> totals;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    const nutrients = [
      (
        key: 'protein_g',
        label: 'Protein',
        unit: 'g',
        icon: Icons.fitness_center_rounded,
        color: Color(0xFF24785B),
        background: Color(0xFFEAF3E9),
      ),
      (
        key: 'carbohydrates_g',
        label: 'Carbohydrates',
        unit: 'g',
        icon: Icons.grain_rounded,
        color: Color(0xFFE0A52F),
        background: Color(0xFFFFF6E3),
      ),
      (
        key: 'total_fat_g',
        label: 'Total fat',
        unit: 'g',
        icon: Icons.water_drop_rounded,
        color: Color(0xFFF07868),
        background: Color(0xFFFFEFEC),
      ),
      (
        key: 'sodium_mg',
        label: 'Sodium',
        unit: 'mg',
        icon: Icons.science_outlined,
        color: Color(0xFF51816F),
        background: Color(0xFFEDF3EE),
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0914231F),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = const _ResultSectionHeading(
                icon: Icons.bar_chart_rounded,
                title: 'Estimated meal nutrition',
              );
              final badge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3E9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'Total for $itemCount ${itemCount == 1 ? 'item' : 'items'}',
                  style: const TextStyle(
                    color: Color(0xFF075B46),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: badge),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  badge,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _EnergyMetric(value: _nutritionValue(totals['energy_kcal'])),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 4 : 2;
              const gap = 7.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 7,
                children: [
                  for (final nutrient in nutrients)
                    SizedBox(
                      width: width,
                      child: _NutritionMetricTile(
                        label: nutrient.label,
                        value: _nutritionValue(totals[nutrient.key]),
                        unit: nutrient.unit,
                        icon: nutrient.icon,
                        color: nutrient.color,
                        background: nutrient.background,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EnergyMetric extends StatelessWidget {
  const _EnergyMetric({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFFFF914D),
            size: 23,
          ),
          const SizedBox(width: 9),
          const Text(
            'Energy',
            style: TextStyle(
              color: Color(0xFF52615A),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value == '—' ? value : '$value kcal',
            style: const TextStyle(
              color: Color(0xFF14231F),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionMetricTile extends StatelessWidget {
  const _NutritionMetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF52615A),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value == '—' ? value : '$value $unit',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF14231F),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionDisclaimerCard extends StatelessWidget {
  const _NutritionDisclaimerCard({required this.totals});

  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    final energy = totals['energy_kcal'];
    final protein = totals['protein_g'];
    final summary = energy == null && protein == null
        ? 'This estimate is based on the food items, portions, and nutrition records you confirmed.'
        : 'This estimate includes ${energy == null ? 'energy unavailable' : '$energy kcal'}'
              '${protein == null ? '' : ' and $protein g of protein'}, based on the foods and portions you confirmed.';
    return _ResultInformationCard(
      icon: Icons.info_outline_rounded,
      text:
          '$summary Actual values can vary with ingredients, cooking methods, oil, and preparation.',
    );
  }
}

class _HealthierSuggestionCard extends StatelessWidget {
  const _HealthierSuggestionCard({
    required this.goalLabel,
    required this.suggestion,
    required this.explanation,
  });

  final String? goalLabel;
  final String suggestion;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: Color(0xFF075B46),
                size: 22,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'A healthier option for your goal',
                  style: TextStyle(
                    color: Color(0xFF14231F),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  goalLabel ?? 'Your goal',
                  style: const TextStyle(
                    color: Color(0xFF075B46),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            suggestion,
            style: const TextStyle(
              color: Color(0xFF345349),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (explanation.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              explanation,
              style: const TextStyle(
                color: Color(0xFF52615A),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportantNotesSection extends StatelessWidget {
  const _ImportantNotesSection({required this.hasAlternativeProduct});

  final bool hasAlternativeProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE8ECE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ResultSectionHeading(
            icon: Icons.description_outlined,
            title: 'Important notes',
          ),
          const SizedBox(height: 10),
          const _ResultNoteRow(
            icon: Icons.monitor_weight_outlined,
            text:
                'Nutrition values are estimates based on the selected USDA records and confirmed portions.',
          ),
          const SizedBox(height: 6),
          const _ResultNoteRow(
            icon: Icons.restaurant_menu_rounded,
            text:
                'Recipes, brands, ingredients, oil, and preparation can change the actual nutrition.',
          ),
          const SizedBox(height: 6),
          _ResultNoteRow(
            icon: hasAlternativeProduct
                ? Icons.shopping_bag_outlined
                : Icons.tips_and_updates_outlined,
            text: hasAlternativeProduct
                ? 'Product listings may be incomplete or outdated. Verify the package label before comparing.'
                : 'The alternative suggestion is general guidance and is not a nutrition-verified replacement.',
          ),
        ],
      ),
    );
  }
}

class _ResultInformationCard extends StatelessWidget {
  const _ResultInformationCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECE5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF24785B), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF58645E),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultNoteRow extends StatelessWidget {
  const _ResultNoteRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF24785B)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF58645E),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _nutritionValue(Object? value) {
  if (value == null) return '—';
  final parsed = double.tryParse(value.toString());
  if (parsed == null) return value.toString();
  return parsed == parsed.roundToDouble()
      ? parsed.toStringAsFixed(0)
      : parsed.toStringAsFixed(1);
}

class _MealReviewScreen extends StatelessWidget {
  const _MealReviewScreen({
    required this.mealName,
    required this.mealType,
    required this.photo,
    required this.components,
    required this.revision,
    required this.componentBuilder,
    required this.onAddItem,
    required this.onSubmit,
    required this.isBusy,
    required this.message,
    required this.messageIsError,
    required this.matchedCount,
    required this.onChangePhoto,
  });

  final TextEditingController mealName;
  final String mealType;
  final XFile photo;
  final List<_MealComponentDraft> components;
  final ValueListenable<int> revision;
  final Widget Function(_MealComponentDraft, int) componentBuilder;
  final VoidCallback onAddItem;
  final Future<void> Function() onSubmit;
  final bool Function() isBusy;
  final String? Function() message;
  final bool Function() messageIsError;
  final int Function() matchedCount;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: revision,
      builder: (context, _) {
        final busy = isBusy();
        final currentMessage = message();
        final matches = matchedCount();
        return Scaffold(
          backgroundColor: const Color(0xFFFAF9F4),
          appBar: AppBar(
            backgroundColor: const Color(0xFFFAF9F4),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 58,
            titleSpacing: 4,
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back to meal photo',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: const Text(
              'Confirm food items',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    const Text(
                      'STEP 2 OF 3',
                      style: TextStyle(
                        color: AppTheme.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var step = 0; step < 3; step++) ...[
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              height: 7,
                              decoration: BoxDecoration(
                                color: step < 2
                                    ? AppTheme.green
                                    : const Color(0xFFDDE5DF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          if (step < 2) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Review your meal',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: const Color(0xFF101820),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.08,
                          ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Review AI suggestions and select the closest nutrition match for each item.',
                      style: TextStyle(
                        color: Color(0xFF657078),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MealPhotoSummaryCard(
                      photo: photo,
                      mealType: mealType,
                      onChangePhoto: onChangePhoto,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mealName,
                      minLines: 1,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Meal name — confirm or edit',
                        prefixIcon: const Icon(
                          Icons.restaurant_menu_rounded,
                          color: AppTheme.green,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFCDD7D2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.green,
                            width: 1.6,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3EB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppTheme.green,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Choose nutrition matches for each food you confirm ($matches of ${components.length} matched). AI suggestions are not verified facts.',
                              style: const TextStyle(
                                color: AppTheme.green,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < components.length; index++) ...[
                      if (index > 0) const SizedBox(height: 12),
                      componentBuilder(components[index], index),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: components.length >= 10 || busy
                          ? null
                          : onAddItem,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        components.length >= 10
                            ? 'Food item limit reached'
                            : 'Add another food item',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppTheme.green,
                        side: const BorderSide(
                          color: AppTheme.green,
                          width: 1.3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (currentMessage != null &&
                        currentMessage.isNotEmpty &&
                        (busy || messageIsError())) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: messageIsError()
                              ? Theme.of(context).colorScheme.errorContainer
                              : const Color(0xFFEAF3EB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            if (busy)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Icon(
                                Icons.error_outline_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(currentMessage)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: busy ? null : onSubmit,
                      icon: busy
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
                        busy
                            ? 'Calculating nutrition…'
                            : matches == components.length
                            ? 'Calculate & save meal'
                            : 'Continue · $matches/${components.length} matched',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: AppTheme.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nutrition is calculated only from the food records and portions you confirm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF657078),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MealPhotoSummaryCard extends StatefulWidget {
  const _MealPhotoSummaryCard({
    required this.photo,
    required this.mealType,
    required this.onChangePhoto,
  });

  final XFile photo;
  final String mealType;
  final VoidCallback onChangePhoto;

  @override
  State<_MealPhotoSummaryCard> createState() => _MealPhotoSummaryCardState();
}

class _MealPhotoSummaryCardState extends State<_MealPhotoSummaryCard> {
  late final _photoBytes = widget.photo.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECE7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D17211E),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: FutureBuilder(
              future: _photoBytes,
              builder: (context, snapshot) => snapshot.hasData
                  ? Image.memory(
                      snapshot.data!,
                      width: 110,
                      height: 92,
                      fit: BoxFit.cover,
                    )
                  : const SizedBox(
                      width: 110,
                      height: 92,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Meal photo',
                  style: TextStyle(
                    color: const Color(0xFF101820).withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.mealType[0].toUpperCase() +
                      widget.mealType.substring(1),
                  style: const TextStyle(
                    color: Color(0xFF101820),
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'AI suggestions are ready to review',
                  style: TextStyle(
                    color: Color(0xFF657078),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onChangePhoto,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Change photo'),
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
