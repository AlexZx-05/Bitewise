class Profile {
  const Profile({required this.id, this.displayName, this.goal});

  final String id;
  final String? displayName;
  final String? goal;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      goal: json['goal'] as String?,
    );
  }

  String? get goalLabel => switch (goal) {
    'fat_loss' => 'Fat loss',
    'muscle_gain' => 'Muscle gain',
    'maintenance' => 'Maintenance',
    _ => null,
  };
}
