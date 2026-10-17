import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/profile.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({required this.onDiary, super.key});

  final VoidCallback onDiary;

  static const _forest = Color(0xFF005A38);
  static const _muted = Color(0xFF687078);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, color: _forest, size: 38),
              const SizedBox(height: 12),
              const Text(
                'Your profile could not be loaded',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(profileProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (value) => LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 380 ? 16.0 : 22.0;
          final compact = constraints.maxHeight < 780;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 8 : 14,
                  horizontalPadding,
                  compact ? 12 : 20,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your Profile',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: _forest,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('edit-profile-button'),
                        onPressed: () => _showEditProfile(context, value),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          foregroundColor: _forest,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 14),
                  _ProfileCard(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 14 : 16,
                      vertical: compact ? 10 : 16,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: compact ? 26 : 32,
                          backgroundColor: AppTheme.sage,
                          child: Text(
                            _initials(_displayName(value)),
                            style: const TextStyle(
                              color: _forest,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName(value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: AppTheme.charcoal,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'rohit@example.com',
                                style: TextStyle(color: _muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.verified_rounded,
                          color: _forest,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 16),
                  _SectionHeading(title: 'Personal information'),
                  SizedBox(height: compact ? 5 : 9),
                  _ProfileCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _InformationRow(
                          icon: Icons.local_fire_department_rounded,
                          iconColor: const Color(0xFFE58A28),
                          label: 'Goal',
                          value: value.goalLabel ?? 'Fat loss',
                          compact: compact,
                        ),
                        _InformationRow(
                          icon: Icons.cake_outlined,
                          label: 'Age',
                          value: value.age == null ? '24' : '${value.age}',
                          compact: compact,
                        ),
                        _InformationRow(
                          icon: Icons.wc_outlined,
                          label: 'Gender',
                          value: _genderLabel(value.gender) ?? 'Male',
                          compact: compact,
                        ),
                        _InformationRow(
                          icon: Icons.height_rounded,
                          label: 'Height',
                          value: _numberLabel(value.heightCm, '175 cm'),
                          compact: compact,
                        ),
                        _InformationRow(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Weight',
                          value: _numberLabel(value.weightKg, '70 kg'),
                          isLast: true,
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 10 : 17),
                  _SectionHeading(title: 'More'),
                  SizedBox(height: compact ? 5 : 9),
                  _ProfileCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _MenuRow(
                          icon: Icons.menu_book_outlined,
                          title: 'Food diary',
                          onTap: onDiary,
                          compact: compact,
                        ),
                        _MenuRow(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          onTap: () => _openDestination(
                            context,
                            'Settings',
                            Icons.settings_outlined,
                            'Personalize your FoodScan experience.',
                          ),
                          compact: compact,
                        ),
                        _MenuRow(
                          icon: Icons.shield_outlined,
                          title: 'Privacy',
                          onTap: () => _openDestination(
                            context,
                            'Privacy',
                            Icons.shield_outlined,
                            'Your profile and food diary are private to you.',
                          ),
                          compact: compact,
                        ),
                        _MenuRow(
                          icon: Icons.support_agent_outlined,
                          title: 'Support',
                          onTap: () => _openDestination(
                            context,
                            'Support',
                            Icons.support_agent_outlined,
                            'Help and support options will be available here.',
                          ),
                          compact: compact,
                        ),
                        _MenuRow(
                          icon: Icons.info_outline_rounded,
                          title: 'About',
                          isLast: true,
                          onTap: () => _openDestination(
                            context,
                            'About FoodScan',
                            Icons.eco_outlined,
                            'FoodScan helps you understand packaged labels '
                                'and everyday meals.',
                          ),
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return 'FS';
    return words.length == 1
        ? words.first.substring(0, 1).toUpperCase()
        : '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'
              .toUpperCase();
  }

  static String _displayName(Profile profile) {
    final name = profile.displayName?.trim();
    return name == null || name.isEmpty ? 'Rohit Sharma' : name;
  }

  static String? _genderLabel(String? gender) => switch (gender) {
    'male' => 'Male',
    'female' => 'Female',
    'other' => 'Other',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => null,
  };

  static String _numberLabel(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    return '${value.replaceFirst(RegExp(r'\.0+$'), '')} ${fallback.split(' ').last}';
  }

  static Future<void> _showEditProfile(BuildContext context, Profile profile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFFFFEF8),
      builder: (context) => _EditProfileSheet(profile: profile),
    );
  }

  static void _openDestination(
    BuildContext context,
    String title,
    IconData icon,
    String description,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileDestinationScreen(
          title: title,
          icon: icon,
          description: description,
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9ECE8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF193528).withValues(alpha: 0.045),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: AppTheme.charcoal,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = const Color(0xFF547064),
    this.isLast = false,
    this.compact = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isLast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
      child: Column(
        children: [
          SizedBox(
            height: compact ? 44 : 52,
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: compact ? 18 : 20),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: ProfileScreen._muted,
                      fontSize: compact ? 13 : 14,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.charcoal,
                      fontSize: compact ? 13 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!isLast)
            const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1EE)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isLast = false,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isLast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: compact ? 48 : 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: const Color(0xFF547064),
                      size: compact ? 19 : 20,
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.charcoal,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: ProfileScreen._muted,
                      size: 21,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 1,
            indent: 48,
            color: Color(0xFFF0F1EE),
          ),
      ],
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  final _formKey = GlobalKey<FormState>();
  late String _goal;
  String? _gender;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ProfileScreen._displayName(widget.profile),
    );
    _age = TextEditingController(text: widget.profile.age?.toString() ?? '24');
    _height = TextEditingController(text: widget.profile.heightCm ?? '175');
    _weight = TextEditingController(text: widget.profile.weightKg ?? '70');
    _goal = widget.profile.goal ?? 'fat_loss';
    _gender = widget.profile.gender ?? 'male';
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).saveDetails({
        'display_name': _name.text.trim(),
        'goal': _goal,
        'age': int.parse(_age.text.trim()),
        'gender': _gender,
        'height_cm': num.parse(_height.text.trim()),
        'weight_kg': num.parse(_weight.text.trim()),
      });
      ref.invalidate(profileProvider);
      if (mounted) Navigator.of(context).pop();
    } on FoodScanApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateNumber(
    String? value, {
    required String label,
    required num minimum,
    required num maximum,
    bool integer = false,
  }) {
    final number = num.tryParse(value?.trim() ?? '');
    if (number == null ||
        !number.isFinite ||
        number < minimum ||
        number > maximum ||
        (integer && number % 1 != 0)) {
      return 'Enter $label from $minimum to $maximum.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final ageField = TextFormField(
      controller: _age,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Age'),
      validator: (value) => _validateNumber(
        value,
        label: 'age',
        minimum: 13,
        maximum: 120,
        integer: true,
      ),
    );
    final heightField = TextFormField(
      controller: _height,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Height (cm)'),
      validator: (value) =>
          _validateNumber(value, label: 'height', minimum: 50, maximum: 250),
    );
    final weightField = TextFormField(
      controller: _weight,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Weight (kg)'),
      validator: (value) =>
          _validateNumber(value, label: 'weight', minimum: 20, maximum: 500),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8DED9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Edit your profile',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) =>
                    value?.trim().isEmpty == true ? 'Enter your name.' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _goal,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Goal',
                  prefixIcon: Icon(Icons.local_fire_department_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'fat_loss', child: Text('Fat loss')),
                  DropdownMenuItem(
                    value: 'muscle_gain',
                    child: Text('Muscle gain'),
                  ),
                  DropdownMenuItem(
                    value: 'maintenance',
                    child: Text('Maintenance'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _goal = value);
                      },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: Icon(Icons.wc_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                  DropdownMenuItem(
                    value: 'prefer_not_to_say',
                    child: Text('Prefer not to say'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = [ageField, heightField, weightField];
                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          if (index > 0) const SizedBox(height: 10),
                          fields[index],
                        ],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (var index = 0; index < fields.length; index++) ...[
                        if (index > 0) const SizedBox(width: 10),
                        Expanded(child: fields[index]),
                      ],
                    ],
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileDestinationScreen extends StatelessWidget {
  const _ProfileDestinationScreen({
    required this.title,
    required this.icon,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F2),
        foregroundColor: AppTheme.green,
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppTheme.sage,
                child: Icon(icon, color: AppTheme.green, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ProfileScreen._muted),
              ),
              const SizedBox(height: 18),
              const Chip(
                label: Text('More options coming soon'),
                avatar: Icon(Icons.auto_awesome_outlined, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
