import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/scanner/presentation/scan_entry_screen.dart';
import '../features/scanner/presentation/packaged_scan_screen.dart';
import '../features/scanner/presentation/meal_scan_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const BootstrapScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/scan', builder: (context, state) => const ScanEntryScreen()),
      GoRoute(
        path: '/scan/packaged',
        builder: (context, state) => const PackagedScanScreen(),
      ),
      GoRoute(
        path: '/scan/meal',
        builder: (context, state) => const MealScanScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
