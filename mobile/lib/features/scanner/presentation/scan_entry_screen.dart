import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class ScanEntryScreen extends StatelessWidget {
  const ScanEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        title: const Text(
          'Choose what to scan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'What are you eating?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a label scan or identify a meal from a photo.',
                style: TextStyle(
                  color: AppTheme.charcoal.withValues(alpha: 0.72),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _ScanChoiceCard(
                icon: Icons.inventory_2_outlined,
                title: 'Packaged food',
                description:
                    'Read ingredients and nutrition information from the label.',
                enabled: true,
                onTap: () => context.push('/scan/packaged'),
              ),
              const SizedBox(height: 12),
              _ScanChoiceCard(
                icon: Icons.ramen_dining_outlined,
                title: 'Home-cooked meal',
                description:
                    'Identify visible foods, confirm portions, then calculate from USDA data.',
                enabled: true,
                onTap: () => context.push('/scan/meal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanChoiceCard extends StatelessWidget {
  const _ScanChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppTheme.sage,
                foregroundColor: AppTheme.green,
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppTheme.charcoal,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!enabled)
                          const Text(
                            'COMING LATER',
                            style: TextStyle(
                              color: AppTheme.green,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppTheme.charcoal.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                enabled ? Icons.arrow_forward_ios : Icons.lock_outline,
                size: 17,
                color: enabled ? AppTheme.green : AppTheme.charcoal.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
