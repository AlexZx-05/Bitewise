import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class PackagedFoodCameraScreen extends StatefulWidget {
  const PackagedFoodCameraScreen({super.key});

  @override
  State<PackagedFoodCameraScreen> createState() =>
      _PackagedFoodCameraScreenState();
}

class _PackagedFoodCameraScreenState extends State<PackagedFoodCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  String? _errorMessage;
  bool _initializing = true;
  bool _busy = false;
  bool _flashOn = false;
  int _cameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize({int? preferredIndex}) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _errorMessage = null;
      });
    }
    CameraController? nextController;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera is available.');
      }
      _cameras = cameras;
      final backCameraIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final index =
          preferredIndex ?? (backCameraIndex >= 0 ? backCameraIndex : 0);
      _cameraIndex = index.clamp(0, cameras.length - 1).toInt();
      nextController = CameraController(
        cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await nextController.initialize();
      if (!mounted) {
        await nextController.dispose();
        return;
      }
      final previousController = _controller;
      setState(() {
        _controller = nextController;
        _initializing = false;
        _flashOn = false;
      });
      if (previousController != null) await previousController.dispose();
    } on CameraException catch (error) {
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    } catch (error) {
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _initializing = false;
        _errorMessage = 'Could not start the camera: $error';
      });
    }
  }

  String _cameraErrorMessage(CameraException error) => switch (error.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Camera access is turned off. Enable camera permission in your device settings and try again.',
    'NoCamera' => 'No camera is available on this device.',
    _ =>
      error.description ?? 'The camera could not be started (${error.code}).',
  };

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    final nextFlashState = !_flashOn;
    try {
      await controller.setFlashMode(
        nextFlashState ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) setState(() => _flashOn = nextFlashState);
    } on CameraException {
      if (mounted) {
        _showMessage('Flash is not available on this camera.');
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_busy || _initializing || _cameras.length < 2) return;
    final nextIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _busy = true);
    try {
      final previousController = _controller;
      _controller = null;
      await previousController?.dispose();
      if (mounted) await _initialize(preferredIndex: nextIndex);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 2000,
      );
      if (file != null && mounted) context.pop(file);
    } catch (error) {
      if (mounted) _showMessage('Could not open the gallery: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_busy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      if (mounted) context.pop(file);
    } on CameraException catch (error) {
      if (mounted) {
        _showMessage(
          error.description ?? 'The photo could not be captured. Please retry.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('The photo could not be captured: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFF17130F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(),
          const ColoredBox(color: Color(0x24140F0A)),
          Positioned(
            top: safeTop + 68,
            left: 24,
            right: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xA6140F0A),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Text(
                  'Keep the label in frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final frameWidth = constraints.maxWidth * 0.86;
                final minTop = safeTop + 140;
                final bottomInset = MediaQuery.paddingOf(context).bottom;
                final availableHeight = math.max(
                  120.0,
                  constraints.maxHeight - minTop - 195 - bottomInset,
                );
                final frameHeight = math.min(
                  math.min(constraints.maxHeight * 0.43, frameWidth * 1.16),
                  availableHeight,
                );
                final maxTop = constraints.maxHeight - frameHeight - 195;
                final frameTop = (constraints.maxHeight * 0.24)
                    .clamp(minTop, math.max(minTop, maxTop))
                    .toDouble();
                return Stack(
                  children: [
                    Positioned(
                      top: frameTop,
                      left: (constraints.maxWidth - frameWidth) / 2,
                      width: frameWidth,
                      height: frameHeight,
                      child: const ScanCornerFrame(),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    SizedBox(
                      width: 76,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => context.pop(),
                          tooltip: 'Back',
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Packaged food',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 76,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: CameraControlButton(
                            icon: _flashOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            label: _flashOn
                                ? 'Turn flash off'
                                : 'Turn flash on',
                            onPressed: _toggleFlash,
                            diameter: 48,
                            active: _flashOn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CameraControlsPanel(
              busy: _busy,
              canFlip: _cameras.length > 1 && !_initializing,
              onGallery: _openGallery,
              onCapture: _capture,
              onFlip: _flipCamera,
            ),
          ),
          if (_initializing)
            const ColoredBox(
              color: Color(0x66140F0A),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          if (_errorMessage case final message?)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xDD17130F),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.no_photography_outlined,
                            color: Colors.white,
                            size: 44,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.tonalIcon(
                            onPressed: _initialize,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                          TextButton(
                            onPressed: () => context.pop(),
                            child: const Text(
                              'Choose photos another way',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_busy && !_initializing)
            const ColoredBox(
              color: Color(0x33140F0A),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF17130F));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cameraAspectRatio = controller.value.aspectRatio;
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxWidth / cameraAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ScanCornerFrame extends StatelessWidget {
  const ScanCornerFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _ScanCornerPainter(),
      child: SizedBox.expand(),
    );
  }
}

class _ScanCornerPainter extends CustomPainter {
  const _ScanCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = (size.width * 0.012).clamp(4.0, 6.0).toDouble();
    final cornerLength = (size.shortestSide * 0.16)
        .clamp(34.0, 54.0)
        .toDouble();
    final radius = 8.0;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final corners = <Path>[
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, radius)
        ..quadraticBezierTo(0, 0, radius, 0)
        ..lineTo(cornerLength, 0),
      Path()
        ..moveTo(size.width - cornerLength, 0)
        ..lineTo(size.width - radius, 0)
        ..quadraticBezierTo(size.width, 0, size.width, radius)
        ..lineTo(size.width, cornerLength),
      Path()
        ..moveTo(0, size.height - cornerLength)
        ..lineTo(0, size.height - radius)
        ..quadraticBezierTo(0, size.height, radius, size.height)
        ..lineTo(cornerLength, size.height),
      Path()
        ..moveTo(size.width - cornerLength, size.height)
        ..lineTo(size.width - radius, size.height)
        ..quadraticBezierTo(
          size.width,
          size.height,
          size.width,
          size.height - radius,
        )
        ..lineTo(size.width, size.height - cornerLength),
    ];
    for (final path in corners) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanCornerPainter oldDelegate) => false;
}

class CameraControlButton extends StatelessWidget {
  const CameraControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.diameter = 58,
    this.active = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double diameter;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: active ? const Color(0xFF5A5148) : const Color(0x1FFFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: diameter,
            child: Icon(icon, color: Colors.white, size: diameter * 0.42),
          ),
        ),
      ),
    );
  }
}

class CameraShutterButton extends StatelessWidget {
  const CameraShutterButton({
    required this.onPressed,
    this.diameter = 82,
    super.key,
  });

  final VoidCallback? onPressed;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture label photo',
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: diameter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraControlsPanel extends StatelessWidget {
  const _CameraControlsPanel({
    required this.busy,
    required this.canFlip,
    required this.onGallery,
    required this.onCapture,
    required this.onFlip,
  });

  final bool busy;
  final bool canFlip;
  final VoidCallback onGallery;
  final VoidCallback onCapture;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
        decoration: const BoxDecoration(
          color: Color(0xCC201A15),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 300;
            final sideDiameter = narrow ? 48.0 : 56.0;
            final shutterDiameter = narrow ? 72.0 : 84.0;
            return Row(
              children: [
                Expanded(
                  child: _LabeledControl(
                    label: 'Gallery',
                    icon: Icons.photo_library_outlined,
                    diameter: sideDiameter,
                    onPressed: busy ? null : onGallery,
                  ),
                ),
                CameraShutterButton(
                  onPressed: busy ? null : onCapture,
                  diameter: shutterDiameter,
                ),
                Expanded(
                  child: _LabeledControl(
                    label: 'Flip',
                    icon: Icons.flip_camera_android_outlined,
                    diameter: sideDiameter,
                    onPressed: busy || !canFlip ? null : onFlip,
                    enabled: canFlip,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.label,
    required this.icon,
    required this.diameter,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final double diameter;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CameraControlButton(
          icon: icon,
          label: label,
          onPressed: onPressed,
          diameter: diameter,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.48),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
