import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/features/onboarding/presentation/camera_permission_screen.dart';
import 'package:mobile/features/onboarding/presentation/profile_details_screen.dart';
import 'package:mobile/features/onboarding/presentation/welcome_screen.dart';
import 'package:mobile/features/scanner/data/label_ocr_parser.dart';
import 'package:mobile/features/scanner/data/meal_scan_repository.dart';
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

  test('profile timeout explains that backend services should be checked', () {
    final error = FoodScanApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/me'),
        type: DioExceptionType.receiveTimeout,
      ),
    );

    expect(error.message, contains('backend and PostgreSQL are running'));
  });

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

  testWidgets('new user completes onboarding and reaches the home screen', (
    tester,
  ) async {
    final repository = FakeProfileRepository();
    final cameraPermissions = FakeCameraPermissionService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
          cameraPermissionServiceProvider.overrideWithValue(cameraPermissions),
        ],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('What is your goal?'), findsOneWidget);
    expect(find.text('Fat loss'), findsOneWidget);
    expect(find.text('Muscle gain'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Fat loss').hitTestable(), findsOneWidget);
    expect(find.text('Muscle gain').hitTestable(), findsOneWidget);
    expect(find.text('Maintenance').hitTestable(), findsOneWidget);
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Fat loss'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.savedGoal, isNull);
    expect(find.byType(ProfileDetailsScreen), findsOneWidget);
    expect(find.text('Tell us a bit about you'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(repository.savedGoal, 'fat_loss');
    expect(find.byType(CameraPermissionScreen), findsOneWidget);
    expect(find.text('Enable camera access'), findsOneWidget);
    await tester.tap(find.text('Allow Camera'));
    await tester.pumpAndSettle();

    expect(cameraPermissions.requestCount, 1);
    expect(find.text('Scan your food'), findsOneWidget);
    expect(find.text('Your goal: Fat loss'), findsOneWidget);
  });

  testWidgets('failed onboarding save shows a profile error', (tester) async {
    final repository = FakeProfileRepository()..failSave = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileDetailsScreen), findsOneWidget);
    expect(find.text('Tell us a bit about you'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the FoodScan API. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Tell us a bit about you'), findsOneWidget);
  });

  testWidgets('returning profiles skip onboarding and open the dashboard', (
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

    expect(find.text('Scan your food'), findsOneWidget);
    expect(find.text('Understand your food better'), findsNothing);
    expect(find.text('What is your goal?'), findsNothing);
  });

  testWidgets('optional onboarding details save before the camera choice', (
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

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muscle gain'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileDetailsScreen), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '24');
    await tester.tap(find.text('Male'));
    final profileList = find.descendant(
      of: find.byType(ProfileDetailsScreen),
      matching: find.byType(ListView),
    );
    final profileScroll = find
        .descendant(of: profileList, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('Height'),
      200,
      scrollable: profileScroll,
    );
    await tester.enterText(find.byType(TextFormField).at(1), '175');
    await tester.scrollUntilVisible(
      find.text('Weight'),
      200,
      scrollable: profileScroll,
    );
    await tester.enterText(find.byType(TextFormField).at(2), '70');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repository.savedDetails, {
      'goal': 'muscle_gain',
      'age': 24,
      'gender': 'male',
      'height_cm': 175,
      'weight_kg': 70,
    });
    expect(find.byType(CameraPermissionScreen), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Scan your food'), findsOneWidget);
  });

  testWidgets('dashboard cards show the summary and open packaged scanning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your goal: Maintenance'), findsOneWidget);
    expect(find.text('Scan nutrition labels'), findsOneWidget);
    expect(find.text('Identify your dish'), findsOneWidget);
    expect(find.text("Today's summary").hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Packaged food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Packaged food'));
    await tester.pumpAndSettle();

    expect(find.text('Capture the label'), findsOneWidget);
    expect(find.text('Choose photos').hitTestable(), findsOneWidget);
    expect(find.text('Take photo').hitTestable(), findsOneWidget);
    expect(
      find
          .text(
            'Some packages print ingredients and nutrition facts on different sides.',
          )
          .hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('bottom scanner button opens the existing scanning flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Diary'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('What do you want to scan?'), findsOneWidget);
    expect(find.text('Scan ingredients and nutrition label'), findsOneWidget);
    expect(
      find.text('Take a photo of your meal and get an estimate'),
      findsOneWidget,
    );
    expect(find.text('Packaged food').hitTestable(), findsOneWidget);
    expect(find.text('Home-cooked meal').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Home-cooked meal'));
    await tester.pumpAndSettle();

    expect(find.text('Home-cooked meal'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Identify meal with AI'), findsNothing);
  });

  testWidgets('packaged food selection opens packaged scanning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Packaged food').hitTestable(), findsOneWidget);
    expect(find.text('Home-cooked meal').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Packaged food'));
    await tester.pumpAndSettle();

    expect(find.text('Capture the label'), findsOneWidget);
    expect(find.text('Choose photos').hitTestable(), findsOneWidget);
    expect(find.text('Take photo').hitTestable(), findsOneWidget);
  });

  testWidgets('scan selection stays within a compact phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeProfileRepository()..savedGoal = 'maintenance';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('What do you want to scan?'), findsOneWidget);
    expect(find.text('Packaged food').hitTestable(), findsOneWidget);
    expect(find.text('Home-cooked meal').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile tab opens profile and its actions work', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = FakeProfileRepository()..savedGoal = 'fat_loss';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
          mealScanRepositoryProvider.overrideWithValue(
            FakeMealScanRepository(),
          ),
        ],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Your Profile'), findsOneWidget);
    expect(find.text('Rohit Sharma'), findsOneWidget);
    expect(find.text('rohit@example.com'), findsOneWidget);
    expect(find.text('Fat loss'), findsOneWidget);
    expect(find.text('175 cm'), findsOneWidget);
    expect(find.text('70 kg'), findsOneWidget);
    expect(find.text('Rohit Sharma').hitTestable(), findsOneWidget);
    expect(find.text('rohit@example.com').hitTestable(), findsOneWidget);
    expect(find.text('Fat loss').hitTestable(), findsOneWidget);
    expect(find.text('175 cm').hitTestable(), findsOneWidget);
    expect(find.text('70 kg').hitTestable(), findsOneWidget);
    expect(find.text('Settings').hitTestable(), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit your profile'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repository.savedDetails['display_name'], 'Rohit Sharma');
    expect(repository.savedDetails['age'], 24);

    await tester.scrollUntilVisible(
      find.text('Settings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Personalize your FoodScan experience.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Food diary'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Food diary'));
    await tester.pumpAndSettle();
    expect(find.text('Your meals'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Home-cooked meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home-cooked meal'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 2  ·  ADD A MEAL PHOTO'), findsOneWidget);
    expect(find.text('Capture your\nhome-cooked meal'), findsOneWidget);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('MEAL TYPE'), findsOneWidget);
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Home-cooked meal analysis is planned for a later milestone.'),
      findsNothing,
    );
  });

  testWidgets('diary dashboard keeps daily summary and meal actions in view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository()..savedGoal = 'maintenance',
          ),
          mealScanRepositoryProvider.overrideWithValue(
            FakeMealScanRepository(),
          ),
        ],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diary'));
    await tester.pumpAndSettle();

    expect(find.text('Your meals').hitTestable(), findsOneWidget);
    expect(find.text('Calories consumed').hitTestable(), findsOneWidget);
    expect(find.text('Add meal').hitTestable(), findsOneWidget);
    expect(find.text('Add your breakfast').hitTestable(), findsOneWidget);
    expect(find.text('Add your lunch').hitTestable(), findsOneWidget);
    expect(find.text('Add your dinner').hitTestable(), findsOneWidget);
    expect(find.text('Add a snack').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Insights tab opens goal-aware recommendations', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository()..savedGoal = 'fat_loss',
          ),
          mealScanRepositoryProvider.overrideWithValue(
            FakeMealScanRepository(),
          ),
        ],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Insights & Suggestions').hitTestable(), findsOneWidget);
    expect(
      find.text('Your selected goal is Fat loss. Explore ideas to compare.'),
      findsOneWidget,
    );
    expect(find.text('Baked Chips').hitTestable(), findsOneWidget);
    expect(find.text('Grilled Chicken').hitTestable(), findsOneWidget);
    expect(find.text('Brown Rice').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Baked Chips'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a product label'), findsOneWidget);

    await tester.tap(find.text('Scan a product label'));
    await tester.pumpAndSettle();
    expect(find.text('Capture the label'), findsOneWidget);
  });

  testWidgets('Insights content fits a compact phone viewport', (tester) async {
    tester.view.physicalSize = const Size(432, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository()..savedGoal = 'muscle_gain',
          ),
          mealScanRepositoryProvider.overrideWithValue(
            FakeMealScanRepository(),
          ),
        ],
        child: const FoodScanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Insights & Suggestions').hitTestable(), findsOneWidget);
    expect(
      find.text('Suggestions for your goal').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Baked Chips').hitTestable(), findsOneWidget);
    expect(find.text('Grilled Chicken').hitTestable(), findsOneWidget);
    expect(find.text('Brown Rice').hitTestable(), findsOneWidget);
    expect(
      find
          .text(
            'General guidance only. Compare serving sizes and product labels.',
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class FakeProfileRepository extends ProfileRepository {
  FakeProfileRepository() : super(Dio());

  String? savedGoal;
  Map<String, dynamic> savedDetails = {};
  bool failSave = false;

  @override
  Future<Profile> getProfile() async => Profile(
    id: 'local-development-profile',
    displayName: savedDetails['display_name'] as String?,
    goal: savedGoal,
    age: savedDetails['age'] as int?,
    gender: savedDetails['gender'] as String?,
    heightCm: savedDetails['height_cm']?.toString(),
    weightKg: savedDetails['weight_kg']?.toString(),
  );

  @override
  Future<Profile> saveGoal(String goal) async {
    if (failSave) {
      throw const FoodScanApiException(
        'Could not reach the FoodScan API. Try again.',
      );
    }
    savedGoal = goal;
    return getProfile();
  }

  @override
  Future<Profile> saveDetails(Map<String, dynamic> details) async {
    if (failSave) {
      throw const FoodScanApiException(
        'Could not reach the FoodScan API. Try again.',
      );
    }
    savedDetails.addAll(details);
    savedGoal = details['goal'] as String? ?? savedGoal;
    return getProfile();
  }
}

class FakeMealScanRepository extends MealScanRepository {
  FakeMealScanRepository() : super(Dio());

  @override
  Future<List<MealScanResult>> getDiary(String date) async => [];
}

class FakeCameraPermissionService extends CameraPermissionService {
  int requestCount = 0;

  @override
  Future<CameraPermissionOutcome> requestAccess() async {
    requestCount++;
    return CameraPermissionOutcome.granted;
  }
}
