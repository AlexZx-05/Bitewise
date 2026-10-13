class PackagedScan {
  const PackagedScan({
    required this.scanId,
    required this.status,
    required this.product,
    required this.findings,
    required this.goalInsight,
    this.llmExplanation,
  });

  final String scanId;
  final String status;
  final PackagedLabel product;
  final List<ScanFinding> findings;
  final String goalInsight;
  final String? llmExplanation;

  factory PackagedScan.fromJson(Map<String, dynamic> json) {
    return PackagedScan(
      scanId: json['scan_id'] as String,
      status: json['status'] as String,
      product: PackagedLabel.fromJson(json['product'] as Map<String, dynamic>),
      findings: (json['findings'] as List<dynamic>)
          .map((item) => ScanFinding.fromJson(item as Map<String, dynamic>))
          .toList(),
      goalInsight: json['goal_insight'] as String,
      llmExplanation: json['llm_explanation'] as String?,
    );
  }
}

class PackagedLabel {
  const PackagedLabel({
    required this.productName,
    required this.servingSizeG,
    required this.nutritionBasis,
    required this.ingredients,
    this.declaredAllergens = const [],
    this.brand,
    this.energyKcal,
    this.proteinG,
    this.carbohydratesG,
    this.totalFatG,
    this.sodiumMg,
    this.precautionaryAllergenStatement,
  });

  final String productName;
  final String? brand;
  final String servingSizeG;
  final String nutritionBasis;
  final String? energyKcal;
  final String? proteinG;
  final String? carbohydratesG;
  final String? totalFatG;
  final String? sodiumMg;
  final List<String> ingredients;
  final List<String> declaredAllergens;
  final String? precautionaryAllergenStatement;

  factory PackagedLabel.fromJson(Map<String, dynamic> json) {
    return PackagedLabel(
      productName: json['product_name'] as String,
      brand: json['brand'] as String?,
      servingSizeG: _asString(json['serving_size_g'])!,
      nutritionBasis: json['nutrition_basis'] as String,
      energyKcal: _asString(json['energy_kcal']),
      proteinG: _asString(json['protein_g']),
      carbohydratesG: _asString(json['carbohydrates_g']),
      totalFatG: _asString(json['total_fat_g']),
      sodiumMg: _asString(json['sodium_mg']),
      ingredients: (json['ingredients'] as List<dynamic>).cast<String>(),
      declaredAllergens:
          (json['declared_allergens'] as List<dynamic>?)?.cast<String>() ??
          const [],
      precautionaryAllergenStatement:
          json['precautionary_allergen_statement'] as String?,
    );
  }

  static String? _asString(dynamic value) => value?.toString();
}

class ScanFinding {
  const ScanFinding({
    required this.category,
    required this.label,
    this.details,
  });

  final String category;
  final String label;
  final String? details;

  factory ScanFinding.fromJson(Map<String, dynamic> json) {
    return ScanFinding(
      category: json['category'] as String,
      label: json['label'] as String,
      details: json['details'] as String?,
    );
  }
}
