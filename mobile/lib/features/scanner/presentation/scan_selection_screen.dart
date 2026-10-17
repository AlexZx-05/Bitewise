import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class ScanSelectionScreen extends StatelessWidget {
  const ScanSelectionScreen({super.key});

  static const _background = Color(0xFFFFFEF8);
  static const _ink = Color(0xFF101820);
  static const _subtitle = Color(0xFF657078);
  static const _green = Color(0xFF064E3B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            final narrow = constraints.maxWidth < 380;
            final horizontalPadding = narrow ? 20.0 : 24.0;
            final cardHeight = compact ? 180.0 : 220.0;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compact ? 4 : 10,
                    horizontalPadding,
                    24,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        tooltip: 'Back',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: _ink,
                          size: 23,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 24),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'What do you want to scan?',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: _ink,
                              fontSize: narrow ? 30 : 34,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                              letterSpacing: -1,
                            ),
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 28),
                    ScanOptionCard(
                      title: 'Packaged food',
                      subtitle: 'Scan ingredients and nutrition label',
                      height: cardHeight,
                      illustration: const _OatmealPackageIllustration(),
                      onTap: () => context.push('/scan/packaged'),
                    ),
                    SizedBox(height: compact ? 14 : 18),
                    ScanOptionCard(
                      title: 'Home-cooked meal',
                      subtitle: 'Take a photo of your meal and get an estimate',
                      height: cardHeight,
                      illustration: const _MealImageIllustration(),
                      onTap: () => context.push('/scan/meal'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ScanOptionCard extends StatelessWidget {
  const ScanOptionCard({
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.onTap,
    this.height = 210,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget illustration;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x161A3328),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: Color(0xFFEAE9E2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final imageWidth = constraints.maxWidth * 0.30;
                  final narrow = constraints.maxWidth < 350;
                  final arrowSize = narrow ? 32.0 : 36.0;
                  return Row(
                    children: [
                      SizedBox(
                        width: imageWidth,
                        height: constraints.maxHeight,
                        child: Center(
                          child: SizedBox.square(
                            dimension: imageWidth,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: ColoredBox(
                                color: const Color(0xFFF8F6EF),
                                child: ExcludeSemantics(child: illustration),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: narrow ? 12 : 17),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: ScanSelectionScreen._ink,
                                    fontSize: narrow ? 19 : 22,
                                    fontWeight: FontWeight.w800,
                                    height: 1.12,
                                    letterSpacing: -0.4,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: ScanSelectionScreen._subtitle,
                                    fontSize: narrow ? 15 : 17,
                                    height: 1.35,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: narrow ? 2 : 6),
                      Container(
                        width: arrowSize,
                        height: arrowSize,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF2ED),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: ScanSelectionScreen._green,
                          size: 23,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OatmealPackageIllustration extends StatelessWidget {
  const _OatmealPackageIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: AspectRatio(
          aspectRatio: 0.76,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 100;
              return Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF7E4B8), Color(0xFFE6C37C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: const Color(0xFFD5B36E)),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: compact ? 7 : 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD8B76F),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(11),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: compact ? 12 : 16,
                      left: 0,
                      right: 0,
                      child: Icon(
                        Icons.eco_rounded,
                        color: AppTheme.green,
                        size: compact ? 17 : 22,
                      ),
                    ),
                    Positioned(
                      top: compact ? 34 : 48,
                      left: 4,
                      right: 4,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 3 : 6,
                            vertical: compact ? 1 : 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.green,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'OATMEAL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 8 : 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: compact ? 4 : 7,
                      left: 0,
                      right: 0,
                      child: Icon(
                        Icons.grain_rounded,
                        color: const Color(0xFF8C672B),
                        size: compact ? 17 : 22,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MealImageIllustration extends StatelessWidget {
  const _MealImageIllustration();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.asset(
        'assets/images/food__welcome.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0.75, -0.25),
        cacheWidth: 360,
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xFFF0F2E9),
          child: Center(
            child: Icon(
              Icons.ramen_dining_rounded,
              color: AppTheme.green,
              size: 42,
            ),
          ),
        ),
      ),
    );
  }
}
