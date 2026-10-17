import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({required this.onCompareProduct, super.key});

  final VoidCallback onCompareProduct;

  static const _recommendations = <_FoodRecommendation>[
    _FoodRecommendation(
      name: 'Baked Chips',
      swap: 'A baked option to compare with regular chips',
      illustration: '🥔',
      color: Color(0xFFFFF1D8),
    ),
    _FoodRecommendation(
      name: 'Grilled Chicken',
      swap: 'A grilled option to compare with fried chicken',
      illustration: '🍗',
      color: Color(0xFFF8E9DA),
    ),
    _FoodRecommendation(
      name: 'Brown Rice',
      swap: 'A whole-grain option to compare with white rice',
      illustration: '🍚',
      color: Color(0xFFF1E9D9),
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppTheme.green)),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 38,
                color: AppTheme.green,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your insights could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(profileProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        final goal = profile.goalLabel;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 20,
                    compact ? 10 : 18,
                    compact ? 16 : 20,
                    compact ? 10 : 20,
                  ),
                  children: [
                    Text(
                      'Insights & Suggestions',
                      style:
                          (compact
                                  ? Theme.of(context).textTheme.titleLarge
                                  : Theme.of(context).textTheme.headlineSmall)
                              ?.copyWith(
                                color: const Color(0xFF111820),
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                    ),
                    SizedBox(height: compact ? 12 : 18),
                    _GoalCard(goal: goal, compact: compact),
                    SizedBox(height: compact ? 16 : 24),
                    Text(
                      'Try these healthier alternatives',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF111820),
                        fontSize: compact ? 16 : null,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    for (final recommendation in _recommendations) ...[
                      _RecommendationCard(
                        recommendation: recommendation,
                        goal: goal,
                        compact: compact,
                        onTap: () =>
                            _showRecommendation(context, recommendation, goal),
                      ),
                      SizedBox(height: compact ? 7 : 10),
                    ],
                    SizedBox(height: compact ? 1 : 4),
                    Text(
                      compact
                          ? 'General guidance only. Compare serving sizes and product labels.'
                          : 'Suggestions are general ideas, not a health assessment. '
                                'Compare each product’s own serving size, ingredients, and nutrition label.',
                      style: TextStyle(
                        color: const Color(0xFF687078),
                        fontSize: compact ? 11 : 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showRecommendation(
    BuildContext context,
    _FoodRecommendation recommendation,
    String? goal,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FoodIllustration(recommendation: recommendation, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      recommendation.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(recommendation.swap, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 8),
              Text(
                goal == null
                    ? 'Choose a goal in your profile to personalize suggestions. Compare product labels before making a choice.'
                    : 'For your ${goal.toLowerCase()} goal, use this as an idea to compare. Check the product label and serving size; this is not an individual dietary recommendation.',
                style: const TextStyle(color: Color(0xFF687078), height: 1.45),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onCompareProduct();
                  },
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan a product label'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.compact});

  final String? goal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 11 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9EBDD)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 54,
            height: compact ? 44 : 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(compact ? 13 : 15),
            ),
            child: Icon(
              Icons.trending_up_rounded,
              color: Color(0xFF159B70),
              size: compact ? 28 : 34,
            ),
          ),
          SizedBox(width: compact ? 11 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal == null
                      ? 'Personalize your suggestions'
                      : 'Suggestions for your goal',
                  style: TextStyle(
                    color: Color(0xFF12432F),
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  goal == null
                      ? 'Set a goal in your profile to tailor food ideas.'
                      : 'Your selected goal is $goal. Explore ideas to compare.',
                  style: TextStyle(
                    color: Color(0xFF3F584A),
                    fontSize: compact ? 12 : 13,
                    height: 1.3,
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

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.goal,
    required this.compact,
    required this.onTap,
  });

  final _FoodRecommendation recommendation;
  final String? goal;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = goal == null
        ? recommendation.swap
        : _goalDescription(recommendation, goal!);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 70 : 88),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE9ECE5)),
          ),
          child: Row(
            children: [
              _FoodIllustration(
                recommendation: recommendation,
                size: compact ? 52 : 64,
              ),
              SizedBox(width: compact ? 11 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      recommendation.name,
                      style: TextStyle(
                        color: Color(0xFF111820),
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF687078),
                        fontSize: compact ? 11 : 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF26322D),
                size: 25,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _goalDescription(_FoodRecommendation item, String goal) {
    return switch (item.name) {
      'Baked Chips' => switch (goal) {
        'Fat loss' => 'Compare serving sizes with regular chips',
        'Muscle gain' => 'Compare snack portions and nutrition labels',
        _ => 'Compare portions with regular chips',
      },
      'Grilled Chicken' => switch (goal) {
        'Muscle gain' => 'Compare protein and serving sizes with fried chicken',
        'Fat loss' => 'Compare portions and preparation methods',
        _ => 'Compare grilled and fried options by serving size',
      },
      'Brown Rice' => switch (goal) {
        'Fat loss' => 'Compare portions and labels with white rice',
        'Muscle gain' => 'Compare whole-grain options and serving sizes',
        _ => 'Compare whole-grain and white-rice options',
      },
      _ => item.swap,
    };
  }
}

class _FoodIllustration extends StatelessWidget {
  const _FoodIllustration({required this.recommendation, required this.size});

  final _FoodRecommendation recommendation;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: recommendation.name,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: recommendation.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          recommendation.illustration,
          style: TextStyle(fontSize: size * 0.55),
        ),
      ),
    );
  }
}

class _FoodRecommendation {
  const _FoodRecommendation({
    required this.name,
    required this.swap,
    required this.illustration,
    required this.color,
  });

  final String name;
  final String swap;
  final String illustration;
  final Color color;
}
