import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';
import '../data/label_ocr_parser.dart';
import '../data/ocr_service.dart';
import '../data/packaged_scan.dart';
import '../data/packaged_scan_repository.dart';

const _maximumLabelPhotos = 3;

class PackagedScanScreen extends ConsumerStatefulWidget {
  const PackagedScanScreen({super.key});

  @override
  ConsumerState<PackagedScanScreen> createState() => _PackagedScanScreenState();
}

class _PackagedScanScreenState extends ConsumerState<PackagedScanScreen> {
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _productName = TextEditingController();
  final _brand = TextEditingController();
  final _servingSize = TextEditingController();
  final _energy = TextEditingController();
  final _protein = TextEditingController();
  final _carbohydrates = TextEditingController();
  final _fat = TextEditingController();
  final _sodium = TextEditingController();
  final _ingredients = TextEditingController();
  final _declaredAllergens = TextEditingController();
  final _precautionary = TextEditingController();
  final _ocrText = TextEditingController();

  final List<_LabelPhoto> _photos = [];
  PackagedScan? _result;
  String _nutritionBasis = 'per_serving';
  String? _errorMessage;
  String? _ocrMessage;
  List<String> _uncertainFields = const [];
  List<String> _missingFields = const [];
  String? _extractionNote;
  bool _isReading = false;
  bool _extractionFailed = false;
  bool _quotaExceeded = false;
  bool _isSubmitting = false;
  bool _showReview = false;
  bool _reviewConfirmed = false;

  @override
  void dispose() {
    _productName.dispose();
    _brand.dispose();
    _servingSize.dispose();
    _energy.dispose();
    _protein.dispose();
    _carbohydrates.dispose();
    _fat.dispose();
    _sodium.dispose();
    _ingredients.dispose();
    _declaredAllergens.dispose();
    _precautionary.dispose();
    _ocrText.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final remaining = _maximumLabelPhotos - _photos.length;
    if (remaining <= 0) return;

    try {
      final files = await _picker.pickMultiImage(
        limit: remaining,
        imageQuality: 82,
        maxWidth: 2000,
      );
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _photos.add(
            _LabelPhoto(
              name: file.name,
              mimeType: file.mimeType ?? 'image/jpeg',
              bytes: bytes,
            ),
          );
          _errorMessage = null;
          _ocrMessage = null;
          _extractionFailed = false;
          _quotaExceeded = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not open the image picker: $error',
        );
      }
    }
  }

  Future<void> _readLabelText() async {
    if (_photos.isEmpty || _isReading) return;
    setState(() {
      _isReading = true;
      _errorMessage = null;
      _ocrMessage = null;
      _extractionFailed = false;
    });

    final textParts = <String>[];
    try {
      for (var index = 0; index < _photos.length; index++) {
        if (mounted) {
          setState(
            () => _ocrMessage =
                'Reading label ${index + 1} of ${_photos.length}…',
          );
        }
        final text = await recognizeLabelText(
          _photos[index].bytes,
          _photos[index].mimeType,
        );
        if (text.trim().isNotEmpty) textParts.add(text.trim());
      }

      if (!mounted) return;
      _ocrText.text = textParts.join('\n\n--- Next label photo ---\n\n');
      final parsed = const LabelOcrParser().parse(_ocrText.text);
      _applyOcrSuggestions(parsed);
      setState(() {
        _ocrMessage = textParts.isEmpty
            ? 'No readable text was detected. You can still enter label details manually.'
            : parsed.detectedFieldCount == 0
            ? 'Text was read, but no label details could be matched confidently. Enter or correct details using the photos.'
            : 'Detected up to ${parsed.detectedFieldCount} possible details. Check and correct every field against the photos.';
        _showReview = true;
        _reviewConfirmed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ocrMessage =
            'OCR could not run ($error). You can continue by entering label details manually.';
        _showReview = true;
        _reviewConfirmed = false;
      });
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  Future<void> _extractLabelWithVision() async {
    if (_photos.isEmpty || _isReading) return;
    setState(() {
      _isReading = true;
      _errorMessage = null;
      _ocrMessage = 'Sending label photos for vision extraction…';
      _extractionFailed = false;
      _quotaExceeded = false;
    });
    try {
      final extracted = await ref
          .read(packagedScanRepositoryProvider)
          .extractLabel(
            _photos
                .map(
                  (photo) => (
                    bytes: photo.bytes,
                    name: photo.name,
                    mimeType: photo.mimeType,
                  ),
                )
                .toList(),
          );
      if (!mounted) return;
      final nutrition = extracted['nutrition'];
      final nutritionData = nutrition is Map<String, dynamic>
          ? nutrition
          : const <String, dynamic>{};
      void fillIfEmpty(TextEditingController controller, dynamic value) {
        if (controller.text.trim().isEmpty && value != null) {
          controller.text = value.toString();
        }
      }

      fillIfEmpty(_productName, extracted['product_name']);
      fillIfEmpty(_brand, extracted['brand']);
      fillIfEmpty(_servingSize, extracted['serving_size_g']);
      fillIfEmpty(_energy, nutritionData['energy_kcal']);
      fillIfEmpty(_protein, nutritionData['protein_g']);
      fillIfEmpty(_carbohydrates, nutritionData['carbohydrates_g']);
      fillIfEmpty(_fat, nutritionData['total_fat_g']);
      fillIfEmpty(_sodium, nutritionData['sodium_mg']);
      final ingredients = extracted['ingredients'];
      if (_ingredients.text.trim().isEmpty && ingredients is List) {
        _ingredients.text = ingredients
            .map((value) => value.toString())
            .join(', ');
      }
      final allergens =
          extracted['declared_allergens'] ?? extracted['allergens'];
      if (_declaredAllergens.text.trim().isEmpty && allergens is List) {
        _declaredAllergens.text = allergens
            .map((value) => value.toString())
            .join(', ');
      }
      fillIfEmpty(
        _precautionary,
        extracted['precautionary_allergen_statement'],
      );
      final basis = extracted['nutrition_basis'];
      if (basis == 'per_serving' || basis == 'per_100g') {
        _nutritionBasis = basis as String;
      }
      final uncertain = extracted['uncertain_fields'];
      final missing = extracted['missing_fields'];
      setState(() {
        _uncertainFields = uncertain is List
            ? uncertain.map((value) => value.toString()).toList()
            : const [];
        _missingFields = missing is List
            ? missing.map((value) => value.toString()).toList()
            : const [];
        _extractionNote = extracted['extraction_note']?.toString();
        _ocrMessage =
            'Vision model filled possible label details. Review and correct every field against the photos.';
        _extractionFailed = false;
        _showReview = true;
        _reviewConfirmed = false;
      });
    } on FoodScanApiException catch (error) {
      if (mounted) {
        setState(() {
          _ocrMessage = error.message;
          _extractionFailed = true;
          _quotaExceeded = error.isQuotaExceeded;
          _showReview = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  void _applyOcrSuggestions(LabelOcrParseResult parsed) {
    void fillIfEmpty(TextEditingController controller, String? value) {
      if (controller.text.trim().isEmpty && value != null) {
        controller.text = value;
      }
    }

    fillIfEmpty(_productName, parsed.productName);
    fillIfEmpty(_servingSize, parsed.servingSizeG);
    fillIfEmpty(_energy, parsed.energyKcal);
    fillIfEmpty(_protein, parsed.proteinG);
    fillIfEmpty(_carbohydrates, parsed.carbohydratesG);
    fillIfEmpty(_fat, parsed.totalFatG);
    fillIfEmpty(_sodium, parsed.sodiumMg);
    fillIfEmpty(_ingredients, parsed.ingredients);
    fillIfEmpty(_precautionary, parsed.precautionaryStatement);
    if (parsed.nutritionBasis != null) {
      _nutritionBasis = parsed.nutritionBasis!;
    }
  }

  void _openReview({bool manually = false}) {
    if (_photos.isEmpty) {
      setState(() {
        _errorMessage =
            'Add at least one clear ingredient or nutrition label photo.';
      });
      return;
    }
    if (_ocrText.text.trim().isEmpty && manually) {
      _ocrMessage =
          'Enter the details exactly as printed. Missing values stay blank.';
    }
    setState(() {
      _errorMessage = null;
      _showReview = true;
      _reviewConfirmed = false;
    });
  }

  Future<void> _analyzeLabel() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    if (!_reviewConfirmed) return;
    if ([
      _energy,
      _protein,
      _carbohydrates,
      _fat,
      _sodium,
    ].every((controller) => controller.text.trim().isEmpty)) {
      setState(
        () => _errorMessage =
            'Enter at least one nutrition value shown on the package. Leave other missing values blank.',
      );
      return;
    }
    final ingredientList = _ingredients.text
        .split(RegExp(r'[\n,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(packagedScanRepositoryProvider).createScan({
        'product_name': _productName.text.trim(),
        'brand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'serving_size_g': _servingSize.text.trim(),
        'nutrition_basis': _nutritionBasis,
        'energy_kcal': _asNumber(_energy.text),
        'protein_g': _asNumber(_protein.text),
        'carbohydrates_g': _asNumber(_carbohydrates.text),
        'total_fat_g': _asNumber(_fat.text),
        'sodium_mg': _asNumber(_sodium.text),
        'ingredients': ingredientList,
        'declared_allergens': _declaredAllergens.text
            .split(RegExp(r'[\n,;]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        'precautionary_allergen_statement': _precautionary.text.trim().isEmpty
            ? null
            : _precautionary.text.trim(),
      });
      if (mounted) setState(() => _result = result);
    } on FoodScanApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  num? _asNumber(String value) {
    if (value.trim().isEmpty) return null;
    return num.parse(value.trim());
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      _ocrText.clear();
      _ocrMessage = null;
    });
  }

  void _startAnotherScan() {
    setState(() {
      _result = null;
      _photos.clear();
      _nutritionBasis = 'per_serving';
      _showReview = false;
      _reviewConfirmed = false;
      _errorMessage = null;
      _ocrMessage = null;
      for (final controller in _inputControllers) {
        controller.clear();
      }
    });
  }

  List<TextEditingController> get _inputControllers => [
    _productName,
    _brand,
    _servingSize,
    _energy,
    _protein,
    _carbohydrates,
    _fat,
    _sodium,
    _ingredients,
    _declaredAllergens,
    _precautionary,
    _ocrText,
  ];

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
        title: Text(
          result == null ? 'Packaged food' : 'Product analysis',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: result != null
                ? _ScanResults(
                    result: result,
                    onAnotherScan: _startAnotherScan,
                    onDone: () => context.pop(),
                  )
                : _showReview
                ? _buildReviewStep()
                : _buildPhotoStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
      children: [
        const _StepIndicator(step: 1),
        const SizedBox(height: 18),
        Text(
          'Capture the label',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Photograph the ingredients and nutrition panel. They may be on different sides of the package.',
          style: TextStyle(
            color: AppTheme.charcoal.withValues(alpha: 0.72),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          kIsWeb
              ? 'Up to 3 JPEG or PNG photos are sent securely to the FoodScan backend for Groq vision extraction. They are not saved; only the details you confirm are stored.'
              : 'Native camera and OCR support will be added after this web prototype.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.charcoal.withValues(alpha: 0.68),
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        const _CaptureGuidance(),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _photos.length >= _maximumLabelPhotos ? null : _addPhotos,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _photos.isEmpty ? 'Choose label photos' : 'Add another label photo',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.green,
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: AppTheme.green),
          ),
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_photos.length} of $_maximumLabelPhotos photos selected',
            style: const TextStyle(
              color: AppTheme.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 126,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _PhotoThumbnail(
                photo: _photos[index],
                onRemove: () => _removePhoto(index),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isReading ? null : _extractLabelWithVision,
            icon: _isReading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(
              _isReading ? 'Extracting label…' : 'Extract label with AI',
            ),
          ),
          TextButton(
            onPressed: _isReading ? null : _readLabelText,
            child: const Text('Use local OCR as a fallback'),
          ),
          TextButton(
            onPressed: _isReading ? null : () => _openReview(manually: true),
            child: const Text('Enter details manually'),
          ),
        ],
        if (_ocrMessage case final message?) ...[
          const SizedBox(height: 8),
          if (_extractionFailed)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF0D4A8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        color: Color(0xFF8A5A13),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _quotaExceeded
                              ? 'AI quota reached'
                              : 'AI extraction did not finish',
                          style: TextStyle(
                            color: Color(0xFF68420D),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$message Your photos are still selected.',
                    style: const TextStyle(
                      color: Color(0xFF68420D),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_quotaExceeded)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _isReading ? null : _readLabelText,
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text('Use local OCR now'),
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isReading ? null : _extractLabelWithVision,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ),
                ],
              ),
            )
          else
            Text(
              message,
              style: TextStyle(
                color: AppTheme.charcoal.withValues(alpha: 0.75),
              ),
            ),
        ],
        if (_errorMessage case final message?) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: message),
        ],
      ],
    );
  }

  Widget _buildReviewStep() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        children: [
          const _StepIndicator(step: 2),
          const SizedBox(height: 18),
          Text(
            'Review the label',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.charcoal,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We filled in details the vision model could read. Confirm or correct each field against the photos. Anything not detected stays blank.',
            style: TextStyle(
              color: AppTheme.charcoal.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
          if (_extractionNote case final note? when note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _NoticeBanner(message: note),
          ],
          if (_uncertainFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            _NoticeBanner(
              message:
                  'Please double-check uncertain fields: ${_uncertainFields.join(', ')}.',
            ),
          ],
          if (_missingFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Not detected in these photos: ${_missingFields.join(', ')}. '
              'Add another clear photo or leave these values blank.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_ocrMessage case final message?) ...[
            const SizedBox(height: 12),
            _NoticeBanner(message: message),
          ],
          if (_ocrText.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Review OCR text'),
              subtitle: const Text('Edit or copy values from this text'),
              children: [
                TextFormField(
                  controller: _ocrText,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    hintText: 'Text read from your label photos',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _sectionHeading('Product details'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _productName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Product name *',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the product name from the package.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _declaredAllergens,
            decoration: const InputDecoration(
              labelText: 'Declared allergens (optional)',
              hintText: 'e.g. Milk, peanuts',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _brand,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Brand (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          _sectionHeading('Serving and nutrition'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _servingSize,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Serving size in grams *',
              hintText: 'e.g. 40',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final number = double.tryParse(value ?? '');
              if (number == null || !number.isFinite || number <= 0) {
                return 'Enter the serving size printed on the package.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _nutritionBasis,
            decoration: const InputDecoration(
              labelText: 'Nutrition values are shown',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'per_serving',
                child: Text('Per serving'),
              ),
              DropdownMenuItem(value: 'per_100g', child: Text('Per 100 g')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _nutritionBasis = value);
            },
          ),
          const SizedBox(height: 12),
          _OptionalNumberField(
            controller: _energy,
            label: 'Energy (kcal)',
            hint: 'Not detected? Leave blank',
          ),
          const SizedBox(height: 10),
          _OptionalNumberField(controller: _protein, label: 'Protein (g)'),
          const SizedBox(height: 10),
          _OptionalNumberField(
            controller: _carbohydrates,
            label: 'Carbohydrates (g)',
          ),
          const SizedBox(height: 10),
          _OptionalNumberField(controller: _fat, label: 'Total fat (g)'),
          const SizedBox(height: 10),
          _OptionalNumberField(controller: _sodium, label: 'Sodium (mg)'),
          const SizedBox(height: 18),
          _sectionHeading('Ingredients and warnings'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _ingredients,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Ingredients (optional)',
              hintText: 'Enter ingredients separated by commas or new lines',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _precautionary,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Precautionary statement (optional)',
              hintText: 'e.g. May contain peanuts',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _reviewConfirmed,
            onChanged: (value) =>
                setState(() => _reviewConfirmed = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I checked these details against the package label.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (_errorMessage case final message?) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: message),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _reviewConfirmed && !_isSubmitting
                ? _analyzeLabel
                : null,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.analytics_outlined),
            label: Text(_isSubmitting ? 'Saving analysis…' : 'Analyze product'),
          ),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() {
                    _showReview = false;
                    _reviewConfirmed = false;
                    _errorMessage = null;
                  }),
            child: const Text('Back to photos'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppTheme.charcoal,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _LabelPhoto {
  const _LabelPhoto({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Text(
      'STEP $step OF 3',
      style: const TextStyle(
        color: AppTheme.green,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _CaptureGuidance extends StatelessWidget {
  const _CaptureGuidance();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.sage,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _GuidanceRow(
              icon: Icons.crop_free,
              text: 'Keep the full label in frame',
            ),
            SizedBox(height: 10),
            _GuidanceRow(
              icon: Icons.wb_sunny_outlined,
              text: 'Use even light and avoid glare or shadows',
            ),
            SizedBox(height: 10),
            _GuidanceRow(
              icon: Icons.text_fields,
              text: 'Make the small print as sharp as possible',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.photo, required this.onRemove});

  final _LabelPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            photo.bytes,
            width: 126,
            height: 126,
            fit: BoxFit.cover,
            semanticLabel: photo.name,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filled(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Remove ${photo.name}',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              minimumSize: const Size(30, 30),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionalNumberField extends StatelessWidget {
  const _OptionalNumberField({
    required this.controller,
    required this.label,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final number = double.tryParse(value.trim());
        if (number == null || !number.isFinite || number < 0) {
          return 'Enter a non-negative number, or leave blank if not on the label.';
        }
        return null;
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => _Banner(
    icon: Icons.error_outline,
    message: message,
    color: Theme.of(context).colorScheme.error,
  );
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => _Banner(
    icon: Icons.info_outline,
    message: message,
    color: AppTheme.green,
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _ScanResults extends StatelessWidget {
  const _ScanResults({
    required this.result,
    required this.onAnotherScan,
    required this.onDone,
  });

  final PackagedScan result;
  final VoidCallback onAnotherScan;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final label = result.product;
    final facts = <(String, String?)>[
      ('Energy', label.energyKcal == null ? null : '${label.energyKcal} kcal'),
      ('Protein', label.proteinG == null ? null : '${label.proteinG} g'),
      (
        'Carbohydrates',
        label.carbohydratesG == null ? null : '${label.carbohydratesG} g',
      ),
      ('Total fat', label.totalFatG == null ? null : '${label.totalFatG} g'),
      ('Sodium', label.sodiumMg == null ? null : '${label.sodiumMg} mg'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
      children: [
        const _StepIndicator(step: 3),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.productName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.charcoal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (label.brand case final brand?) ...[
                  const SizedBox(height: 4),
                  Text(brand),
                ],
                const SizedBox(height: 8),
                Text(
                  'Serving ${label.servingSizeG} g · '
                  '${label.nutritionBasis == 'per_100g' ? 'values per 100 g' : 'values per serving'}',
                  style: const TextStyle(color: AppTheme.green),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _ResultHeading('Nutrition facts'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final (index, fact) in facts.indexed)
                _FactRow(
                  label: fact.$1,
                  value: fact.$2 ?? 'Not provided',
                  last: index == facts.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ResultHeading('Ingredients'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              label.ingredients.isEmpty
                  ? 'No ingredients were entered from the label.'
                  : label.ingredients.join(', '),
            ),
          ),
        ),
        if (label.declaredAllergens.isNotEmpty) ...[
          const SizedBox(height: 18),
          _ResultHeading('Declared allergens'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(label.declaredAllergens.join(', ')),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _ResultHeading('Label findings'),
        const SizedBox(height: 8),
        if (result.findings.isEmpty)
          const _FindingCard(
            icon: Icons.info_outline,
            title: 'No supported findings detected',
            detail:
                'This does not mean the product is allergen-free. Check the full package label.',
          )
        else
          for (final finding in result.findings) ...[
            _FindingCard(
              icon: finding.category.contains('allergen')
                  ? Icons.warning_amber_rounded
                  : Icons.notes_outlined,
              title: finding.label,
              detail: finding.details ?? '',
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        _ResultHeading('Nutrition context'),
        const SizedBox(height: 8),
        _FindingCard(
          icon: Icons.tips_and_updates_outlined,
          title: 'Based on your selected goal',
          detail: result.goalInsight,
        ),
        if (result.llmExplanation case final explanation?) ...[
          const SizedBox(height: 18),
          _ResultHeading('Personalized explanation'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(explanation),
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Save to food diary — coming later'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onAnotherScan,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Scan another product'),
        ),
        TextButton(onPressed: onDone, child: const Text('Back to home')),
      ],
    );
  }
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      color: AppTheme.charcoal,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    required this.last,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (!last) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.green),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(detail),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
