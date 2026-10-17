import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';

enum CameraPermissionOutcome {
  granted,
  denied,
  permanentlyDenied,
  unavailable,
}

class CameraPermissionService {
  Future<CameraPermissionOutcome> requestAccess() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return CameraPermissionOutcome.unavailable;
    }

    final status = await Permission.camera.request();
    if (status.isGranted) return CameraPermissionOutcome.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionOutcome.permanentlyDenied;
    }
    return CameraPermissionOutcome.denied;
  }

  Future<CameraPermissionOutcome> checkAccess() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return CameraPermissionOutcome.unavailable;
    }

    final status = await Permission.camera.status;
    if (status.isGranted) return CameraPermissionOutcome.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionOutcome.permanentlyDenied;
    }
    return CameraPermissionOutcome.denied;
  }

  Future<bool> openSettings() => openAppSettings();
}

final cameraPermissionServiceProvider = Provider<CameraPermissionService>(
  (ref) => CameraPermissionService(),
);

class CameraPermissionScreen extends ConsumerStatefulWidget {
  const CameraPermissionScreen({this.initialGoal, super.key});

  final String? initialGoal;

  @override
  ConsumerState<CameraPermissionScreen> createState() =>
      _CameraPermissionScreenState();
}

class _CameraPermissionScreenState
    extends ConsumerState<CameraPermissionScreen> {
  CameraPermissionOutcome? _outcome;
  bool _requesting = false;
  bool _checking = false;
  bool _openedSettings = false;
  String? _errorMessage;

  Future<void> _requestCameraAccess() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _errorMessage = null;
    });

    try {
      final outcome = await ref
          .read(cameraPermissionServiceProvider)
          .requestAccess();
      if (!mounted) return;
      if (outcome == CameraPermissionOutcome.granted ||
          outcome == CameraPermissionOutcome.unavailable) {
        context.go('/home');
        return;
      }
      setState(() => _outcome = outcome);
    } on PlatformException {
      if (mounted) {
        setState(() {
          _errorMessage =
              'We could not open the camera permission prompt. You can '
              'continue without camera access.';
        });
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _openSettings() async {
    setState(() {
      _checking = true;
      _errorMessage = null;
    });
    try {
      final opened = await ref
          .read(cameraPermissionServiceProvider)
          .openSettings();
      if (!mounted) return;
      setState(() {
        _openedSettings = opened;
        if (!opened) {
          _errorMessage = 'Could not open device settings. You can continue '
              'without camera access.';
        }
      });
    } on PlatformException {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not open device settings. You can continue '
              'without camera access.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _checkCameraAccess() async {
    setState(() {
      _checking = true;
      _errorMessage = null;
    });
    try {
      final outcome = await ref
          .read(cameraPermissionServiceProvider)
          .checkAccess();
      if (!mounted) return;
      if (outcome == CameraPermissionOutcome.granted ||
          outcome == CameraPermissionOutcome.unavailable) {
        context.go('/home');
        return;
      }
      setState(() {
        _outcome = outcome;
        _errorMessage = 'Camera access is still turned off. You can enable it '
            'in Settings or continue without camera access.';
      });
    } on PlatformException {
      if (mounted) {
        setState(() {
          _errorMessage = 'We could not check camera access. You can continue '
              'without camera access.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _goBack() =>
      context.go('/onboarding/profile', extra: widget.initialGoal);

  void _continueWithoutCamera() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied =
        _outcome == CameraPermissionOutcome.permanentlyDenied;
    final hasDenied =
        _outcome == CameraPermissionOutcome.denied || permanentlyDenied;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFEF8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, compact ? 8 : 18, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: _goBack,
                            tooltip: 'Back to profile details',
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                          ),
                          const Spacer(),
                          const _OnboardingProgress(),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ),
                      SizedBox(height: compact ? 14 : 30),
                      Center(
                        child: Container(
                          width: compact ? 132 : 168,
                          height: compact ? 132 : 168,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF2E9),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 88,
                              height: 72,
                              decoration: BoxDecoration(
                                color: const Color(0xFF086443),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 20 : 26),
                      Text(
                        'Enable camera access',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 30 : 34,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: const Color(0xFF101820),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        kIsWeb
                            ? 'Your browser will ask for camera access when '
                                  'you choose to scan a meal or food label.'
                            : 'We use camera access to scan food labels and '
                                  'analyze meal photos. You can also choose a '
                                  'photo from your device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 17 : 19,
                          height: 1.45,
                          color: const Color(0xFF686B72),
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 26),
                      if (_errorMessage != null || hasDenied) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _errorMessage ??
                                (permanentlyDenied
                                    ? 'Camera access is turned off for '
                                          'FoodScan. You can enable it in '
                                          'Settings or continue without it.'
                                    : 'Camera access was not granted. You can '
                                          'continue and choose a photo instead.'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppTheme.charcoal,
                                  height: 1.4,
                                ),
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 18 : 26),
                      _PrivacyCard(compact: compact),
                    ],
                  ),
                );
              },
            ),
          ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _requesting || _checking
                          ? null
                          : permanentlyDenied
                          ? _openSettings
                          : _requestCameraAccess,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _requesting || _checking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              kIsWeb
                                  ? 'Continue to FoodScan'
                                  : permanentlyDenied
                                  ? 'Open Settings'
                                  : hasDenied
                                  ? 'Try again'
                                  : 'Allow Camera',
                            ),
                    ),
                  ),
                  if (_openedSettings) ...[
                    TextButton(
                      onPressed: _checking ? null : _checkCameraAccess,
                      child: const Text('I enabled camera access'),
                    ),
                  ],
                  TextButton(
                    onPressed: _requesting || _checking
                        ? null
                        : _continueWithoutCamera,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 44),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Not now'),
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

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Onboarding step 3 of 4',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          4,
          (index) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 30,
            height: 7,
            decoration: BoxDecoration(
              color: index < 3
                  ? const Color(0xFF086443)
                  : const Color(0xFFE5E5E3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5ED),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 32,
            color: Color(0xFF086443),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your privacy matters',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF101820),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Photos are used to analyze food. You choose when to take '
                  'or select a photo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF686B72),
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
