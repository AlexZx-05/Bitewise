class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.goal,
    this.age,
    this.gender,
    this.heightCm,
    this.weightKg,
  });

  final String id;
  final String? displayName;
  final String? goal;
  final int? age;
  final String? gender;
  final String? heightCm;
  final String? weightKg;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      goal: json['goal'] as String?,
      age: json['age'] as int?,
      gender: json['gender'] as String?,
      heightCm: json['height_cm']?.toString(),
      weightKg: json['weight_kg']?.toString(),
    );
  }

  String? get goalLabel => switch (goal) {
    'fat_loss' => 'Fat loss',
    'muscle_gain' => 'Muscle gain',
    'maintenance' => 'Maintenance',
    _ => null,
  };
}
