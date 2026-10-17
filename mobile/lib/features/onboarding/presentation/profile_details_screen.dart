import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';
import 'welcome_screen.dart';

class ProfileDetailsScreen extends ConsumerStatefulWidget {
  const ProfileDetailsScreen({this.initialGoal, super.key});

  final String? initialGoal;

  @override
  ConsumerState<ProfileDetailsScreen> createState() =>
      _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends ConsumerState<ProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  String? _gender;
  String? _errorMessage;
  bool _saving = false;

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _continue({bool skip = false}) async {
    if (_saving) return;
    if (!skip && !_formKey.currentState!.validate()) return;

    final details = <String, dynamic>{};
    final goal = widget.initialGoal;
    if (goal != null) details['goal'] = goal;
    if (!skip) {
      final age = int.tryParse(_age.text.trim());
      final height = num.tryParse(_height.text.trim());
      final weight = num.tryParse(_weight.text.trim());
      if (age != null) details['age'] = age;
      if (_gender != null) details['gender'] = _gender;
      if (height != null) details['height_cm'] = height;
      if (weight != null) details['weight_kg'] = weight;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      if (details.isNotEmpty) {
        await ref.read(profileRepositoryProvider).saveDetails(details);
        ref.invalidate(profileProvider);
      }
      if (mounted) {
        context.go('/onboarding/camera', extra: widget.initialGoal);
      }
    } on FoodScanApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateNumber(
    String? value, {
    required String label,
    required double minimum,
    required double maximum,
    bool integer = false,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = num.tryParse(text);
    if (number == null ||
        !number.isFinite ||
        number < minimum ||
        number > maximum ||
        (integer && number % 1 != 0)) {
      return 'Enter $label from ${minimum.toStringAsFixed(0)} to '
          '${maximum.toStringAsFixed(0)}.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7EF),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/onboarding', extra: widget.initialGoal),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to goal selection',
        ),
        title: const OnboardingProgress(currentStep: 2, totalSteps: 4),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxHeight < 720 ||
                      MediaQuery.sizeOf(context).width < 520;
                  final sectionGap = compact ? 11.0 : 18.0;

                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      compact ? 10 : 16,
                      24,
                      compact ? 12 : 20,
                    ),
                    children: [
                      Text(
                        'ABOUT YOU  ·  OPTIONAL',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: AppTheme.green,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tell us a bit about you',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontSize: compact ? 29 : null,
                              color: AppTheme.charcoal,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              height: 1.1,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optional details help personalize your insights.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: compact ? 15 : null,
                          color: AppTheme.charcoal.withValues(alpha: 0.72),
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      Text(
                        'Age',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _NumberField(
                        controller: _age,
                        hint: '24',
                        dense: compact,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _validateNumber(
                          value,
                          label: 'an age',
                          minimum: 13,
                          maximum: 120,
                          integer: true,
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      Text(
                        'Gender',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _genderChoice('male', 'Male', compact: compact),
                          _genderChoice('female', 'Female', compact: compact),
                          _genderChoice('other', 'Other', compact: compact),
                          _genderChoice(
                            'prefer_not_to_say',
                            'Prefer not to say',
                            compact: compact,
                          ),
                        ],
                      ),
                      SizedBox(height: sectionGap),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Height',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                _NumberField(
                                  controller: _height,
                                  hint: '175',
                                  suffix: 'cm',
                                  dense: compact,
                                  textInputAction: TextInputAction.next,
                                  validator: (value) => _validateNumber(
                                    value,
                                    label: 'a height',
                                    minimum: 50,
                                    maximum: 250,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Weight',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                _NumberField(
                                  controller: _weight,
                                  hint: '70',
                                  suffix: 'kg',
                                  dense: compact,
                                  textInputAction: TextInputAction.done,
                                  validator: (value) => _validateNumber(
                                    value,
                                    label: 'a weight',
                                    minimum: 20,
                                    maximum: 500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      Container(
                        padding: EdgeInsets.all(compact ? 10 : 13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4EE),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.green.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              color: AppTheme.green,
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'These details are optional and do not change '
                                'nutrition results.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: compact ? 10 : null,
                                      color: AppTheme.charcoal.withValues(
                                        alpha: 0.72,
                                      ),
                                      height: 1.3,
                                    ),
                              ),
                            ),
                          ],
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _errorMessage == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _continue,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _saving
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
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _continue(skip: true),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Skip for now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _genderChoice(String value, String label, {required bool compact}) {
    final selected = _gender == value;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2EC) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppTheme.green : const Color(0xFFD9DCD8),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              setState(() {
                _gender = value;
                _errorMessage = null;
              });
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 14,
                vertical: compact ? 8 : 11,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppTheme.green : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? AppTheme.green
                            : const Color(0xFF969B96),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.charcoal.withValues(alpha: 0.88),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.hint,
    required this.validator,
    required this.textInputAction,
    required this.dense,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final String? suffix;
  final FormFieldValidator<String> validator;
  final TextInputAction textInputAction;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: const Color(0xFFFFFEFC),
        isDense: dense,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 17,
          vertical: dense ? 13 : 17,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9DCD8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.green, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
