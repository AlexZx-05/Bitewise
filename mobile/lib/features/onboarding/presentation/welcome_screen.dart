import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7EF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = (constraints.maxWidth * 0.1)
              .clamp(24.0, 56.0)
              .toDouble();
          final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/food__welcome.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                semanticLabel:
                    'A colorful bowl of grilled chicken, vegetables, and grains',
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.68, 1],
                      colors: [
                        Colors.transparent,
                        Color(0x00FAF7EF),
                        Color(0x70FAF7EF),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottomInset + 28,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SizedBox(
                        width: double.infinity,
                        height: 72,
                        child: FilledButton(
                          onPressed: () => context.go('/onboarding'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.green,
                            foregroundColor: Colors.white,
                            elevation: 8,
                            shadowColor: AppTheme.green.withValues(alpha: 0.24),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    required this.currentStep,
    this.totalSteps = 3,
    super.key,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) =>
      _ProgressDots(currentStep: currentStep, totalSteps: totalSteps);
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.currentStep, this.totalSteps = 3});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Onboarding step ${currentStep + 1} of $totalSteps',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalSteps, (index) {
          final selected = index == currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: selected ? 38 : 25,
            height: 8,
            decoration: BoxDecoration(
              color: selected ? AppTheme.green : const Color(0xFFD9DAD4),
              borderRadius: BorderRadius.circular(8),
            ),
          );
        }),
      ),
    );
  }
}
