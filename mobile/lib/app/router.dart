import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/presentation/camera_permission_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/profile_details_screen.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/scanner/presentation/meal_scan_screen.dart';
import '../features/scanner/presentation/packaged_food_camera_screen.dart';
import '../features/scanner/presentation/packaged_scan_screen.dart';
import '../features/scanner/presentation/scan_selection_screen.dart';
import 'app.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const BootstrapScreen()),
      GoRoute(
        path: '/splash',
        builder: (context, state) =>
            SplashScreen(hasCompletedOnboarding: state.extra == true),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(
          initialGoal: switch (state.extra) {
            final String goal => goal,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => ProfileDetailsScreen(
          initialGoal: switch (state.extra) {
            final String goal => goal,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '/onboarding/camera',
        builder: (context, state) => CameraPermissionScreen(
          initialGoal: switch (state.extra) {
            final String goal => goal,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeEntryScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanSelectionScreen(),
      ),
      GoRoute(
        path: '/scan/packaged',
        builder: (context, state) => const PackagedScanScreen(),
      ),
      GoRoute(
        path: '/scan/packaged/camera',
        builder: (context, state) => const PackagedFoodCameraScreen(),
      ),
      GoRoute(
        path: '/scan/meal',
        builder: (context, state) {
          final requestedType = state.uri.queryParameters['type'];
          const mealTypes = {'breakfast', 'lunch', 'dinner', 'snack'};
          return MealScanScreen(
            initialMealType: mealTypes.contains(requestedType)
                ? requestedType!
                : 'lunch',
          );
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
