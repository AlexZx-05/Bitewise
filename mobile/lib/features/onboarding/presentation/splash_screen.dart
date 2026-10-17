import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.hasCompletedOnboarding, super.key});

  final bool hasCompletedOnboarding;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _entryController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1800),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            context.go(widget.hasCompletedOnboarding ? '/home' : '/welcome');
          }
        });
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/foodscan_splash.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          semanticLabel: 'FoodScan splash screen',
        ),
      ),
    );
  }
}
