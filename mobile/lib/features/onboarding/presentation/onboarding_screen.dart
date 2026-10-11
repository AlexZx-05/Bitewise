import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';

enum FoodGoal {
  fatLoss('fat_loss', 'Fat loss', 'Understand calories and make informed choices.'),
  muscleGain(
    'muscle_gain',
    'Muscle gain',
    'Pay attention to protein, energy, and balanced meals.',
  ),
  maintenance(
    'maintenance',
    'Maintenance',
    'Track your food and maintain your current routine.',
  );

  const FoodGoal(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  FoodGoal? _selectedGoal;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _continue() async {
    final goal = _selectedGoal;
    if (goal == null || _isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(profileRepositoryProvider).saveGoal(goal.value);
      ref.invalidate(profileProvider);
      if (mounted) context.go('/home');
    } on FoodScanApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              children: [
                const _BrandMark(),
                const SizedBox(height: 40),
                Text(
                  'What is your goal?',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.charcoal,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We’ll personalize your food insights around what matters to you.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.charcoal.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                for (final goal in FoodGoal.values) ...[
                  _GoalCard(
                    goal: goal,
                    selected: _selectedGoal == goal,
                    onTap: () => setState(() {
                      _selectedGoal = goal;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_errorMessage case final message?) ...[
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _selectedGoal == null || _isSaving ? null : _continue,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your goal helps organize food insights. It does not set a medical or calorie prescription.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.charcoal.withValues(alpha: 0.65),
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

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.sage,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.eco_outlined, color: AppTheme.green),
        ),
        const SizedBox(width: 12),
        Text(
          'FOODSCAN',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTheme.green,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final FoodGoal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${goal.label}. ${goal.description}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? AppTheme.sage : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppTheme.green : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.label,
                      style: const TextStyle(
                        color: AppTheme.charcoal,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      goal.description,
                      style: TextStyle(
                        color: AppTheme.charcoal.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppTheme.green : AppTheme.charcoal.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
