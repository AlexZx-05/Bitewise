import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/app.dart';
import 'package:mobile/features/profile/data/profile.dart';
import 'package:mobile/features/profile/data/profile_repository.dart';

void main() {
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
