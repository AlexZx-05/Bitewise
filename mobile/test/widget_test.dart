import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/features/scanner/data/label_ocr_parser.dart';
import 'package:mobile/features/profile/data/profile.dart';
import 'package:mobile/features/profile/data/profile_repository.dart';

void main() {
  test(
    'API receive timeout explains that the request may still be processing',
    () {
      final error = FoodScanApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/scans/packaged/extract',
          ),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(error.message, contains('AI provider may be busy'));
      expect(error.message, contains('retry'));
    },
  );

  test('API response errors preserve the backend detail', () {
    final error = FoodScanApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/scans/packaged/extract'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(
            path: '/api/v1/scans/packaged/extract',
          ),
          statusCode: 503,
          data: const {
            'detail': 'Groq is temporarily busy. Please retry shortly.',
          },
        ),
      ),
    );

    expect(error.message, contains('Groq is temporarily busy'));
  });

  test('Groq usage-limit errors are identified for the local OCR fallback', () {
    final error = FoodScanApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/scans/packaged/extract'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(
            path: '/api/v1/scans/packaged/extract',
          ),
          statusCode: 503,
          data: const {
            'detail': 'Groq API rate or usage limit reached. Use local OCR.',
          },
        ),
      ),
    );

    expect(error.isQuotaExceeded, isTrue);
    expect(error.message, contains('rate or usage limit reached'));
  });

  test('OCR parser suggests visible label details for user review', () {
    const text = '''
Kurkure Masala Munch
Nutrition Information
Serving Size 30 g
Per 100 g
Energy 150 kcal
Protein 2 g
Carbohydrates 16 g
Total Fat 8 g
Sodium 220 mg
Ingredients: corn meal, edible vegetable oil, spices
May contain peanuts
''';

    final parsed = const LabelOcrParser().parse(text);

    expect(parsed.productName, 'Kurkure Masala Munch');
    expect(parsed.servingSizeG, '30');
    expect(parsed.nutritionBasis, 'per_100g');
    expect(parsed.energyKcal, '150');
    expect(parsed.proteinG, '2');
    expect(parsed.carbohydratesG, '16');
    expect(parsed.totalFatG, '8');
    expect(parsed.sodiumMg, '220');
    expect(parsed.ingredients, 'corn meal, edible vegetable oil, spices');
    expect(parsed.precautionaryStatement, 'May contain peanuts');
  });

  test('OCR parser leaves nutrition facts blank when not found', () {
    final parsed = const LabelOcrParser().parse('Nutrition Information');

    expect(parsed.energyKcal, isNull);
    expect(parsed.proteinG, isNull);
    expect(parsed.detectedFieldCount, 0);
  });

  test('OCR parser does not treat nutrition headings as product names', () {
    final parsed = const LabelOcrParser().parse(
      'Nutrition Information\nPer 100 g\nEnergy 480 kJ',
    );

    expect(parsed.productName, isNull);
  });

  test('OCR parser keeps inline may-contain text out of ingredients', () {
    final parsed = const LabelOcrParser().parse(
      'Ingredients: corn, salt. May contain peanuts',
    );

    expect(parsed.ingredients, 'corn, salt.');
    expect(parsed.precautionaryStatement, 'May contain peanuts');
  });

  testWidgets('user selects a goal, saves it, and reaches the home screen', (
    tester,
  ) async {
    final repository = FakeProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('What is your goal?'), findsOneWidget);
    await tester.tap(find.text('Fat loss'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.savedGoal, 'fat_loss');
    expect(find.text('Scan your food'), findsOneWidget);
    expect(find.text('Your goal: Fat loss'), findsOneWidget);
  });

  testWidgets('failed goal save shows a retryable error', (tester) async {
    final repository = FakeProfileRepository()..failSave = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maintenance'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the FoodScan API. Try again.'),
      findsOneWidget,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('What is your goal?'), findsOneWidget);
  });

  testWidgets('home opens the packaged-food scanner', (tester) async {
    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Choose what to scan'), findsOneWidget);
    await tester.tap(find.text('Packaged food'));
    await tester.pumpAndSettle();

    expect(find.text('Capture the label'), findsOneWidget);
    expect(find.text('Choose label photos'), findsOneWidget);
    expect(find.text('Home-cooked meal'), findsNothing);
  });

  testWidgets('home opens the confirmed USDA meal-scanning flow', (
    tester,
  ) async {
    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home-cooked meal'));
    await tester.pumpAndSettle();

    expect(find.text('Home-cooked meal'), findsOneWidget);
    expect(find.text('Choose meal photo'), findsOneWidget);
    expect(find.text('Identify meal with AI'), findsNothing);
  });

  testWidgets('home meal tile opens the meal confirmation workflow', (
    tester,
  ) async {
    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Home-cooked meal'), 250);
    await tester.tap(find.text('Home-cooked meal'));
    await tester.pumpAndSettle();

    expect(find.text('Photo → confirm → nutrition estimate'), findsOneWidget);
    expect(find.text('Choose meal photo'), findsOneWidget);
    expect(
      find.text('Home-cooked meal analysis is planned for a later milestone.'),
      findsNothing,
    );
  });
}

class FakeProfileRepository extends ProfileRepository {
  FakeProfileRepository() : super(Dio());

  String? savedGoal;
  bool failSave = false;

  @override
  Future<Profile> getProfile() async =>
      Profile(id: 'local-development-profile', goal: savedGoal);

  @override
  Future<Profile> saveGoal(String goal) async {
    if (failSave) {
      throw const FoodScanApiException(
        'Could not reach the FoodScan API. Try again.',
      );
    }
    savedGoal = goal;
    return Profile(id: 'local-development-profile', goal: goal);
  }
}
