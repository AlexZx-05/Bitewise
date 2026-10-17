import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/profile/data/profile_repository.dart';
import 'router.dart';

class FoodScanApp extends ConsumerWidget {
  const FoodScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'FoodScan',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class BootstrapScreen extends ConsumerWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: profile.when(
            loading: () => const _BootstrapLoading(),
            error: (error, stackTrace) => _LoadError(
              message: error.toString(),
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: (value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.go('/splash', extra: value.goal != null);
                }
              });
              return const CircularProgressIndicator();
            },
          ),
        ),
      ),
    );
  }
}

class HomeEntryScreen extends ConsumerWidget {
  const HomeEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () => const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, stackTrace) => _LoadError(
        message: error.toString(),
        onRetry: () => ref.invalidate(profileProvider),
      ),
      data: (value) {
        if (value.goal == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/');
          });
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        return const HomeScreen();
      },
    );
  }
}

class _BootstrapLoading extends StatelessWidget {
  const _BootstrapLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.sage,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.eco_rounded,
              color: AppTheme.green,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Preparing FoodScan',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.charcoal,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connecting to your profile…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.charcoal.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 16),
          const Text(
            'FoodScan could not connect',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
