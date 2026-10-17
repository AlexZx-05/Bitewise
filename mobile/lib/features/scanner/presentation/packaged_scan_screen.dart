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
import 'alternative_product_card.dart';

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

  Future<void> _openCamera() async {
    if (_photos.length >= _maximumLabelPhotos) return;
    final file = await context.push<XFile>('/scan/packaged/camera');
    if (file == null) return;

    try {
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
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not load the selected photo: $error',
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
          onPressed: () {
            if (result != null) {
              setState(() {
                _result = null;
                _showReview = true;
                _reviewConfirmed = true;
                _errorMessage = null;
              });
            } else if (_showReview) {
              setState(() {
                _showReview = false;
                _errorMessage = null;
              });
            } else {
              context.pop();
            }
          },
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
                    uploadedImage: _photos.isEmpty ? null : _photos.first.bytes,
                    uploadedImageName: _photos.isEmpty
                        ? null
                        : _photos.first.name,
                    onAnotherScan: _startAnotherScan,
                    onDone: () => context.go('/home'),
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
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final compact = width < 420;
    final dense = screenSize.height < 850;
    final headingSize = dense
        ? 30.0
        : compact
        ? 32.0
        : 40.0;
    final bodySize = dense
        ? 15.0
        : compact
        ? 16.0
        : 19.0;
    final noteSize = dense
        ? 12.0
        : compact
        ? 13.0
        : 16.0;

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: _BotanicalBackground()),
        ),
        ListView(
          padding: EdgeInsets.fromLTRB(
            compact ? 22 : 26,
            dense ? 8 : 14,
            compact ? 22 : 26,
            dense ? 14 : 30,
          ),
          children: [
            const _StepIndicator(step: 1),
            SizedBox(height: dense ? 14 : 28),
            Text(
              'Capture the label',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF101820),
                fontSize: headingSize,
                height: dense ? 1.02 : 1.08,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            SizedBox(height: dense ? 8 : 14),
            Text(
              'Photograph the ingredients and nutrition panel. They may be on different sides of the package.',
              style: TextStyle(
                color: const Color(0xFF626C72),
                fontSize: bodySize,
                height: dense ? 1.3 : 1.42,
              ),
            ),
            SizedBox(height: dense ? 12 : 22),
            Text(
              'Up to 3 JPEG or PNG photos can be uploaded for ingredient and nutrition analysis. Your scan is saved after you review and confirm the details.',
              style: TextStyle(
                color: const Color(0xFF808991),
                fontSize: noteSize,
                height: dense ? 1.3 : 1.45,
              ),
            ),
            SizedBox(
              height: dense
                  ? 14
                  : compact
                  ? 22
                  : 30,
            ),
            const _CaptureGuidance(),
            SizedBox(
              height: dense
                  ? 12
                  : compact
                  ? 20
                  : 28,
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final tight = constraints.maxWidth < 330;
                final buttonTextSize = tight
                    ? 13.0
                    : compact
                    ? 14.0
                    : 17.0;
                final horizontalPadding = tight
                    ? 8.0
                    : compact
                    ? 10.0
                    : 18.0;
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _photos.length >= _maximumLabelPhotos
                            ? null
                            : _addPhotos,
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: compact ? 21 : 26,
                        ),
                        label: Text(
                          'Choose photos',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: buttonTextSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF075B45),
                          minimumSize: Size.fromHeight(
                            dense
                                ? 54
                                : compact
                                ? 58
                                : 76,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          side: const BorderSide(
                            color: Color(0xFF075B45),
                            width: 1.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _photos.length >= _maximumLabelPhotos
                            ? null
                            : _openCamera,
                        icon: Icon(
                          Icons.camera_alt_outlined,
                          size: compact ? 21 : 26,
                        ),
                        label: Text(
                          'Take photo',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: buttonTextSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF075B45),
                          foregroundColor: Colors.white,
                          minimumSize: Size.fromHeight(
                            dense
                                ? 54
                                : compact
                                ? 58
                                : 76,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 18),
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
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
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
                onPressed: _isReading
                    ? null
                    : () => _openReview(manually: true),
                child: const Text('Enter details manually'),
              ),
            ],
            SizedBox(height: dense ? 12 : 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_rounded,
                    color: Color(0xFF899398),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Some packages print ingredients and nutrition facts on different sides.',
                    style: TextStyle(
                      color: const Color(0xFF808991),
                      fontSize: noteSize,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            if (_ocrMessage case final message?) ...[
              const SizedBox(height: 12),
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
                          const Icon(
                            Icons.cloud_off_outlined,
                            color: Color(0xFF8A5A13),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _quotaExceeded
                                  ? 'AI quota reached'
                                  : 'AI extraction did not finish',
                              style: const TextStyle(
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
                            onPressed: _isReading
                                ? null
                                : _extractLabelWithVision,
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
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final hasExtractionNotices =
        (_extractionNote?.isNotEmpty ?? false) ||
        _uncertainFields.isNotEmpty ||
        _missingFields.isNotEmpty ||
        (_ocrMessage?.isNotEmpty ?? false);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        children: [
          const _StepIndicator(step: 2),
          const SizedBox(height: 22),
          Text(
            'Review the label',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF101820),
              fontSize: 32,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'We filled in details the vision model could read. Confirm or correct each field against the photos. Anything not detected stays blank.',
            style: TextStyle(
              color: const Color(0xFF59656D),
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (_extractionNote case final note? when note.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ExtractionNoticeCard(message: note),
          ],
          if (_uncertainFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtractionNoticeCard(
              message:
                  'Please double-check uncertain fields: ${_uncertainFields.join(', ')}.',
            ),
          ],
          if (_missingFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ExtractionNoticeCard(
              message:
                  'Not detected in these photos: ${_missingFields.join(', ')}. '
                  'Add another clear photo or leave these values blank.',
            ),
          ],
          if (_ocrMessage case final message?) ...[
            const SizedBox(height: 10),
            _ExtractionNoticeCard(message: message),
          ],
          if (!hasExtractionNotices) ...[
            const SizedBox(height: 12),
            const _ExtractionNoticeCard(
              message:
                  'Review every value against the package label. Undetected details are left blank.',
            ),
          ],
          if (_ocrText.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text(
                  'Review OCR text',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Edit or copy values from this text'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  TextFormField(
                    controller: _ocrText,
                    minLines: 4,
                    maxLines: 10,
                    decoration: _reviewInputDecoration(
                      controller: _ocrText,
                      hint: 'Text read from your label photos',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _ReviewSectionCard(
            title: 'Product details',
            icon: Icons.shopping_bag_outlined,
            children: [
              TextFormField(
                controller: _productName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: _reviewInputDecoration(
                  controller: _productName,
                  label: 'Product name *',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter the product name from the package.'
                    : null,
              ),
              TextFormField(
                controller: _declaredAllergens,
                textInputAction: TextInputAction.next,
                decoration: _reviewInputDecoration(
                  controller: _declaredAllergens,
                  label: 'Declared allergens (optional)',
                  hint: 'e.g. Milk, peanuts',
                ),
              ),
              TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: _reviewInputDecoration(
                  controller: _brand,
                  label: 'Brand (optional)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReviewSectionCard(
            title: 'Serving and nutrition',
            icon: Icons.restaurant_outlined,
            children: [
              TextFormField(
                controller: _servingSize,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: _reviewInputDecoration(
                  controller: _servingSize,
                  label: 'Serving size in grams *',
                  hint: 'e.g. 40',
                ),
                validator: (value) {
                  final number = double.tryParse(value ?? '');
                  if (number == null || !number.isFinite || number <= 0) {
                    return 'Enter the serving size printed on the package.';
                  }
                  return null;
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _nutritionBasis,
                decoration: _reviewInputDecoration(
                  label: 'Nutrition values are shown',
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
              _OptionalNumberField(
                controller: _energy,
                label: 'Energy (kcal)',
                hint: 'Not detected? Leave blank',
              ),
              _OptionalNumberField(controller: _protein, label: 'Protein (g)'),
              _OptionalNumberField(
                controller: _carbohydrates,
                label: 'Carbohydrates (g)',
              ),
              _OptionalNumberField(controller: _fat, label: 'Total fat (g)'),
              _OptionalNumberField(controller: _sodium, label: 'Sodium (mg)'),
            ],
          ),
          const SizedBox(height: 14),
          _ReviewSectionCard(
            title: 'Ingredients and warnings',
            icon: Icons.fact_check_outlined,
            children: [
              TextFormField(
                controller: _ingredients,
                minLines: 3,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: _reviewInputDecoration(
                  controller: _ingredients,
                  label: 'Ingredients (optional)',
                  hint: 'Enter ingredients separated by commas or new lines',
                  alignLabelWithHint: true,
                ),
              ),
              TextFormField(
                controller: _precautionary,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                decoration: _reviewInputDecoration(
                  controller: _precautionary,
                  label: 'Precautionary statement (optional)',
                  hint: 'e.g. May contain peanuts',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: CheckboxListTile(
                value: _reviewConfirmed,
                onChanged: (value) =>
                    setState(() => _reviewConfirmed = value ?? false),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFF075B45),
                title: const Text(
                  'I checked these details against the package label.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF075B45),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
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

InputDecoration _reviewInputDecoration({
  String? label,
  TextEditingController? controller,
  String? hint,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: const Color(0xFFFFFEFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFC5C9C7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFC5C9C7)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF075B45), width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.6),
    ),
    suffixIcon: controller == null
        ? null
        : ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: controller.clear,
                    tooltip: 'Clear ${label ?? 'field'}',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF7A858C),
                      size: 19,
                    ),
                  ),
          ),
  );
}

class _ReviewSectionCard extends StatelessWidget {
  const _ReviewSectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EAE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x090F2018),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF101820),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F0E9),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF075B45), size: 21),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _ExtractionNoticeCard extends StatelessWidget {
  const _ExtractionNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: Color(0xFFD7E7D9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF075B45),
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF315D4E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP $step OF 3',
          style: const TextStyle(
            color: Color(0xFF075B45),
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                height: 10,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 10),
                decoration: BoxDecoration(
                  color: index < step
                      ? const Color(0xFF075B45)
                      : const Color(0xFFDCE4DD),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaptureGuidance extends StatelessWidget {
  const _CaptureGuidance();

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 420;
    final dense = screenSize.height < 850;
    return Container(
      padding: EdgeInsets.all(
        dense
            ? 13
            : compact
            ? 17
            : 24,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6EC).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFD5E4D4), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12075B45),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: dense
                    ? 36
                    : compact
                    ? 40
                    : 48,
                height: dense
                    ? 36
                    : compact
                    ? 40
                    : 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFDDEBDD),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.eco_rounded,
                  color: const Color(0xFF075B45),
                  size: dense
                      ? 21
                      : compact
                      ? 24
                      : 29,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Tips for a clear scan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF101820),
                    fontSize: dense
                        ? 16
                        : compact
                        ? 17
                        : 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 14),
                const Expanded(
                  child: Divider(color: Color(0xFFD5E4D4), thickness: 1.4),
                ),
              ],
            ],
          ),
          SizedBox(
            height: dense
                ? 4
                : compact
                ? 8
                : 16,
          ),
          const _GuidanceRow(
            icon: Icons.crop_free_rounded,
            title: 'Keep the full label in frame',
            description: 'Capture all ingredients and nutrition details.',
          ),
          const _GuidanceDivider(),
          const _GuidanceRow(
            icon: Icons.wb_sunny_outlined,
            title: 'Use good lighting',
            description: 'Avoid glare, reflections, and shadows.',
          ),
          const _GuidanceDivider(),
          const _GuidanceRow(
            icon: Icons.text_fields_rounded,
            title: 'Keep text sharp',
            description: 'Make sure small print is readable.',
          ),
        ],
      ),
    );
  }
}

class _GuidanceDivider extends StatelessWidget {
  const _GuidanceDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 62),
      child: Divider(
        height: 1,
        thickness: 1,
        color: const Color(0xFFD5E4D4).withValues(alpha: 0.85),
      ),
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 420;
    final dense = screenSize.height < 850;
    final iconSize = dense
        ? 38.0
        : compact
        ? 48.0
        : 62.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: dense
            ? 6
            : compact
            ? 12
            : 18,
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFDDEBDD),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF075B45),
              size: dense
                  ? 21
                  : compact
                  ? 25
                  : 31,
            ),
          ),
          SizedBox(
            width: dense
                ? 10
                : compact
                ? 12
                : 18,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF101820),
                    fontSize: dense
                        ? 14
                        : compact
                        ? 14
                        : 18,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: const Color(0xFF626C72),
                    fontSize: dense
                        ? 11
                        : compact
                        ? 12
                        : 15,
                    height: dense ? 1.2 : 1.35,
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

class _BotanicalBackground extends StatelessWidget {
  const _BotanicalBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _BotanicalPainter());
  }
}

class _BotanicalPainter extends CustomPainter {
  const _BotanicalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0xFFBFD7BD).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF8EB28A).withValues(alpha: 0.52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawLeaf(Offset center, double width, double height, double rotation) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      final leaf = Path()
        ..moveTo(0, height / 2)
        ..cubicTo(
          -width / 2,
          height / 5,
          -width / 2,
          -height / 3,
          0,
          -height / 2,
        )
        ..cubicTo(width / 2, -height / 3, width / 2, height / 5, 0, height / 2)
        ..close();
      canvas.drawPath(leaf, fill);
      canvas.drawLine(Offset(0, height / 2), Offset(0, -height / 2), stroke);
      canvas.restore();
    }

    drawLeaf(Offset(size.width * 0.98, size.height * 0.13), 58, 150, 0.5);
    drawLeaf(Offset(size.width * 0.90, size.height * 0.11), 44, 112, -0.48);
    drawLeaf(Offset(size.width * 1.02, size.height * 0.88), 72, 174, -0.54);
    drawLeaf(Offset(size.width * 0.91, size.height * 0.91), 46, 124, 0.48);
  }

  @override
  bool shouldRepaint(covariant _BotanicalPainter oldDelegate) => false;
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
      decoration: _reviewInputDecoration(
        controller: controller,
        label: label,
        hint: hint,
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
    required this.uploadedImage,
    required this.uploadedImageName,
    required this.onAnotherScan,
    required this.onDone,
  });

  final PackagedScan result;
  final Uint8List? uploadedImage;
  final String? uploadedImageName;
  final VoidCallback onAnotherScan;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final label = result.product;
    final servingSize = label.servingSizeG.trim();
    final servingBasis = label.nutritionBasis == 'per_100g'
        ? 'Per 100 g'
        : servingSize.isEmpty
        ? 'Per serving'
        : 'Per serving ($servingSize g)';
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
    final providedExplanation = result.llmExplanation;
    final explanation =
        providedExplanation != null && providedExplanation.trim().isNotEmpty
        ? providedExplanation
        : _buildLabelExplanation(label, facts);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        const _StepIndicator(step: 3),
        const SizedBox(height: 14),
        _ProductSummaryCard(
          label: label,
          servingBasis: servingBasis,
          image: uploadedImage,
          imageName: uploadedImageName,
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.bar_chart_rounded,
          title: 'Nutrition facts',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0E6),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              servingBasis,
              style: const TextStyle(
                color: Color(0xFF075B45),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child: Column(
            children: [
              for (final (index, fact) in facts.indexed)
                _FactRow(
                  label: fact.$1,
                  value: fact.$2 ?? 'Not available',
                  last: index == facts.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.eco_outlined,
          title: 'Ingredients',
          child: _IngredientsContent(ingredients: label.ingredients),
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.shield_outlined,
          title: 'Declared allergens',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.declaredAllergens.isEmpty)
                const Text(
                  'No declared allergens detected. This does not confirm that the product is allergen-free.',
                  style: TextStyle(height: 1.4, color: Color(0xFF66717A)),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final allergen in label.declaredAllergens)
                      _AllergenChip(label: allergen),
                  ],
                ),
              if (label.precautionaryAllergenStatement case final statement?
                  when statement.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Precautionary statement',
                        style: TextStyle(
                          color: Color(0xFF9D2929),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statement,
                        style: const TextStyle(
                          color: Color(0xFF66717A),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.warning_amber_rounded,
          title: 'Label findings',
          iconColor: const Color(0xFFE52424),
          child: result.findings.isEmpty
              ? const Text(
                  'No additional findings were confirmed. Review the full package label, especially if you have an allergy.',
                  style: TextStyle(height: 1.4, color: Color(0xFF66717A)),
                )
              : Column(
                  children: [
                    for (final (index, finding) in result.findings.indexed) ...[
                      _FindingTile(finding: finding),
                      if (index < result.findings.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.tips_and_updates_outlined,
          title: 'Nutrition context',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0E6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD4E7D8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline,
                    color: AppTheme.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Based on your selected goal',
                        style: TextStyle(
                          color: Color(0xFF075B45),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.goalInsight,
                        style: const TextStyle(
                          color: Color(0xFF485B52),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (result.analysisNotice case final notice?
            when notice.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _FindingCard(
            icon: Icons.info_outline,
            title: 'AI guidance unavailable',
            detail: notice,
          ),
        ],
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.article_outlined,
          title: 'Personalized explanation',
          child: Text(
            explanation,
            style: const TextStyle(
              color: Color(0xFF48515A),
              height: 1.45,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ResultSection(
          icon: Icons.spa_outlined,
          title: 'A healthier option for your goal',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F0E6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: AppTheme.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.goalAlternative ??
                        'Compare the serving size and confirmed nutrition values with similar products. Suitability depends on your overall needs and daily targets.',
                    style: const TextStyle(
                      color: Color(0xFF485B52),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'General information only. Check the product’s own label; nutrition and ingredients may vary.',
          style: TextStyle(
            color: Color(0xFF66717A),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        if (result.alternativeProduct case final product?) ...[
          const SizedBox(height: 12),
          const _ResultHeading('Product to compare'),
          const SizedBox(height: 6),
          AlternativeProductCard(product: product),
        ] else if (result.alternativeProductNotice case final notice?
            when notice.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            notice,
            style: const TextStyle(color: Color(0xFF66717A), fontSize: 12),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Food diary saving is coming soon.')),
          ),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Save to food diary · Coming soon'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAnotherScan,
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Scan another product'),
        ),
        TextButton(onPressed: onDone, child: const Text('Back to home')),
      ],
    );
  }

  String _buildLabelExplanation(
    PackagedLabel label,
    List<(String, String?)> facts,
  ) {
    final availableFacts = facts
        .where((fact) => fact.$2 != null)
        .map((fact) => '${fact.$1.toLowerCase()}: ${fact.$2}')
        .toList();
    final serving = label.servingSizeG.trim().isEmpty
        ? 'the listed serving'
        : 'a ${label.servingSizeG} g serving';
    if (availableFacts.isEmpty) {
      return 'Nutrition values were not available in the confirmed label data for $serving. Check the package for the complete nutrition information.';
    }
    return 'Based on the confirmed label, $serving lists '
        '${availableFacts.join(', ')}. These values describe the package label and are not a dietary recommendation.';
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

class _ProductSummaryCard extends StatelessWidget {
  const _ProductSummaryCard({
    required this.label,
    required this.servingBasis,
    required this.image,
    required this.imageName,
  });

  final PackagedLabel label;
  final String servingBasis;
  final Uint8List? image;
  final String? imageName;

  @override
  Widget build(BuildContext context) {
    final brand = label.brand?.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9ECE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3ED),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: image == null
                ? const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFF718078),
                    size: 30,
                  )
                : Image.memory(
                    image!,
                    fit: BoxFit.cover,
                    semanticLabel: imageName ?? 'Uploaded product label photo',
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF718078),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111820),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                if (brand != null && brand.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    brand,
                    style: const TextStyle(
                      color: Color(0xFF66717A),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  servingBasis,
                  style: const TextStyle(
                    color: Color(0xFF075B45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Color(0xFF46534D)),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.iconColor = const Color(0xFF075B45),
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9ECE5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 23),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF111820),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _IngredientsContent extends StatefulWidget {
  const _IngredientsContent({required this.ingredients});

  final List<String> ingredients;

  @override
  State<_IngredientsContent> createState() => _IngredientsContentState();
}

class _IngredientsContentState extends State<_IngredientsContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.ingredients.isEmpty
        ? 'Ingredient information could not be confirmed from the label.'
        : widget.ingredients.join(', ');
    final canExpand = text.length > 260;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: canExpand && !_expanded ? 5 : null,
          overflow: canExpand && !_expanded ? TextOverflow.ellipsis : null,
          style: const TextStyle(
            color: Color(0xFF48515A),
            height: 1.4,
            fontSize: 14,
          ),
        ),
        if (canExpand)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(_expanded ? 'Show less' : 'Show more'),
            ),
          ),
      ],
    );
  }
}

class _AllergenChip extends StatelessWidget {
  const _AllergenChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFDCEBFA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF174A70),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final ScanFinding finding;

  @override
  Widget build(BuildContext context) {
    final isAllergen = finding.category.toLowerCase().contains('allergen');
    final detail = finding.details?.trim();
    final hasDetail = detail != null && detail.isNotEmpty;
    final tone = isAllergen ? const Color(0xFFE52424) : const Color(0xFF075B45);
    return Material(
      color: isAllergen ? const Color(0xFFFFF5F2) : const Color(0xFFF6F8F5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: hasDetail
            ? () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          finding.label,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(detail),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isAllergen ? Icons.warning_amber_rounded : Icons.notes_outlined,
                color: tone,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finding.label,
                      style: const TextStyle(
                        color: Color(0xFF20262B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasDetail) ...[
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF66717A),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasDetail) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF66717A),
                  size: 21,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
