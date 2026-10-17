import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import 'welcome_screen.dart';

enum FoodGoal {
  fatLoss(
    'fat_loss',
    'Fat loss',
    'Understand calories and make informed food choices.',
  ),
  muscleGain(
    'muscle_gain',
    'Muscle gain',
    'Focus on protein, energy and balanced meals.',
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

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({this.initialGoal, super.key});

  final String? initialGoal;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  FoodGoal? _selectedGoal;

  @override
  void initState() {
    super.initState();
    for (final goal in FoodGoal.values) {
      if (goal.value == widget.initialGoal) {
        _selectedGoal = goal;
        break;
      }
    }
  }

  void _continue() {
    final goal = _selectedGoal;
    if (goal == null) return;
    context.push('/onboarding/profile', extra: goal.value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7EF),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/welcome'),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to welcome',
        ),
        title: const OnboardingProgress(currentStep: 1, totalSteps: 4),
        centerTitle: true,
        toolbarHeight: 64,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                MediaQuery.sizeOf(context).width < 400 ||
                constraints.maxHeight < 620;
            final horizontalPadding = compact ? 20.0 : 24.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 10 : 16,
                horizontalPadding,
                compact ? 8 : 12,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'YOUR PERSONAL PLAN',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppTheme.green,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'What is your goal?',
                        style: TextStyle(
                          fontSize: compact ? 27 : 32,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF171D27),
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 10),
                      Text(
                        'We’ll personalize your food insights around what '
                        'matters to you.',
                        style: TextStyle(
                          fontSize: compact ? 15 : 18,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF4D5663),
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 18),
                      Expanded(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < FoodGoal.values.length;
                              index++
                            ) ...[
                              Expanded(
                                child: _GoalCard(
                                  goal: FoodGoal.values[index],
                                  selected:
                                      _selectedGoal == FoodGoal.values[index],
                                  compact: compact,
                                  onTap: () => setState(() {
                                    _selectedGoal = FoodGoal.values[index];
                                  }),
                                ),
                              ),
                              if (index < FoodGoal.values.length - 1)
                                SizedBox(height: compact ? 8 : 12),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 10),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 15,
                            color: AppTheme.green.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Goals personalize insights, not medical advice.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    color: AppTheme.charcoal.withValues(
                                      alpha: 0.68,
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedGoal == null ? null : _continue,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final FoodGoal goal;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = switch (goal) {
      FoodGoal.fatLoss => (
        Icons.local_fire_department_rounded,
        const Color(0xFFFF633E),
      ),
      FoodGoal.muscleGain => (
        Icons.fitness_center_rounded,
        const Color(0xFF50565D),
      ),
      FoodGoal.maintenance => (Icons.spa_rounded, const Color(0xFF25846B)),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: '${goal.label}. ${goal.description}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF8FCF6) : const Color(0xFFFFFEFA),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: selected
                ? const Color(0xFF176B52)
                : const Color(0xFFE9E7E0),
            width: selected ? 1.8 : 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(23),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 8 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? 42 : 58,
                    child: Center(
                      child: Icon(
                        icon,
                        color: iconColor,
                        size: compact ? 34 : 42,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.label,
                          style: TextStyle(
                            fontSize: compact ? 18 : 21,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                            height: 1.2,
                          ),
                        ),
                        SizedBox(height: compact ? 3 : 5),
                        Text(
                          goal.description,
                          style: TextStyle(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF555D68),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? const Color(0xFF176B52)
                          : Colors.transparent,
                      border: selected
                          ? null
                          : Border.all(
                              color: const Color(0xFFCDD0CC),
                              width: 2,
                            ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: compact ? 19 : 22,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
