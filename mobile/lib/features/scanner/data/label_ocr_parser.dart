class LabelOcrParser {
  const LabelOcrParser();

  LabelOcrParseResult parse(String text) {
    final lines = text
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.trim())
        .toList();

    return LabelOcrParseResult(
      productName: _productName(lines),
      servingSizeG: _servingSize(lines),
      nutritionBasis: _nutritionBasis(text),
      energyKcal: _nutritionValue(lines, _energyLabel, energy: true),
      proteinG: _nutritionValue(lines, _proteinLabel),
      carbohydratesG: _nutritionValue(lines, _carbohydrateLabel),
      totalFatG: _nutritionValue(lines, _fatLabel),
      sodiumMg: _nutritionValue(lines, _sodiumLabel),
      ingredients: _ingredients(lines),
      precautionaryStatement: _precautionaryStatement(lines),
    );
  }

  static final _energyLabel = RegExp(
    r'^(energy|calories)\b',
    caseSensitive: false,
  );
  static final _proteinLabel = RegExp(r'^protein\b', caseSensitive: false);
  static final _carbohydrateLabel = RegExp(
    r'^(total\s+)?carbohydrates?\b',
    caseSensitive: false,
  );
  static final _fatLabel = RegExp(r'^(total\s+)?fat\b', caseSensitive: false);
  static final _sodiumLabel = RegExp(r'^sodium\b', caseSensitive: false);
  static final _number = RegExp(r'\d+(?:[.,]\d+)?');
  static final _servingPattern = RegExp(
    r'(?:serving\s*size|serving|serves)\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:g|grams)\b',
    caseSensitive: false,
  );
  static final _warningStart = RegExp(
    r'\b(may contain|might contain|contains traces of|'
    r'manufactured in a facility|processed in a facility)\b',
    caseSensitive: false,
  );

  String? _productName(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('---')) break;
      if (line.isEmpty) continue;
      if (RegExp(
        r'^(nutrition|nutrition facts|nutrition information|ingredients|'
        r'product details|allergen information|serving size|'
        r'per\s*(?:100\s*g|serving)|nutrition values)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        break;
      }
      if (_energyLabel.hasMatch(line) ||
          _proteinLabel.hasMatch(line) ||
          _carbohydrateLabel.hasMatch(line) ||
          _fatLabel.hasMatch(line) ||
          _sodiumLabel.hasMatch(line) ||
          _servingPattern.hasMatch(line) ||
          RegExp(r'^\d').hasMatch(line)) {
        continue;
      }
      if (line.length < 2 || line.length > 80) continue;
      return line
          .replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9)]+$'), '')
          .trim();
    }
    return null;
  }

  String? _servingSize(List<String> lines) {
    for (final line in lines) {
      final match = _servingPattern.firstMatch(line);
      if (match != null) return _normalizedNumber(match.group(1)!);
    }
    return null;
  }

  String? _nutritionBasis(String text) {
    if (RegExp(
      r'per\s*100\s*g\b|100\s*g\s*(?:basis|values)',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'per_100g';
    }
    if (RegExp(r'per\s*serv(?:e|ing)\b', caseSensitive: false).hasMatch(text)) {
      return 'per_serving';
    }
    return null;
  }

  String? _nutritionValue(
    List<String> lines,
    RegExp label, {
    bool energy = false,
  }) {
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final match = label.firstMatch(line);
      if (match == null) continue;

      final valueText = line.substring(match.end);
      final value =
          _parseNutritionNumber(valueText, energy: energy) ??
          (index + 1 < lines.length
              ? _parseNutritionNumber(lines[index + 1], energy: energy)
              : null);
      if (value != null) return value;
    }
    return null;
  }

  String? _parseNutritionNumber(String text, {required bool energy}) {
    if (energy) {
      final kcalMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*kcal\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (kcalMatch != null) return _normalizedNumber(kcalMatch.group(1)!);

      final kjMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*kJ\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (kjMatch != null) {
        final kilojoules = double.tryParse(
          _normalizedNumber(kjMatch.group(1)!),
        );
        if (kilojoules != null) {
          return (kilojoules * 0.239006).toStringAsFixed(1);
        }
      }
    }

    final match = _number.firstMatch(text);
    return match == null ? null : _normalizedNumber(match.group(0)!);
  }

  String? _ingredients(List<String> lines) {
    final collected = <String>[];
    var readingIngredients = false;

    for (final line in lines) {
      if (line.startsWith('---')) {
        if (readingIngredients) break;
        continue;
      }
      final match = RegExp(
        r'\bingredients?\s*[:\-]?',
        caseSensitive: false,
      ).firstMatch(line);
      if (!readingIngredients && match != null) {
        readingIngredients = true;
        final remainder = line.substring(match.end).trim();
        final warning = _warningStart.firstMatch(remainder);
        final ingredients = warning == null
            ? remainder
            : remainder.substring(0, warning.start).trim();
        if (ingredients.isNotEmpty) collected.add(ingredients);
        if (warning != null) break;
        continue;
      }
      if (!readingIngredients) continue;
      if (_isSectionBoundary(line)) break;
      final warning = _warningStart.firstMatch(line);
      final ingredientLine = warning == null
          ? line
          : line.substring(0, warning.start).trim();
      if (ingredientLine.isNotEmpty) collected.add(ingredientLine);
      if (warning != null) break;
    }

    final value = collected.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.isEmpty ? null : value;
  }

  String? _precautionaryStatement(List<String> lines) {
    final statements = <String>[];
    for (final line in lines) {
      final warning = _warningStart.firstMatch(line);
      if (warning != null) statements.add(line.substring(warning.start).trim());
    }
    return statements.isEmpty ? null : statements.join(' ');
  }

  bool _isSectionBoundary(String line) {
    return RegExp(
      r'^(may contain|might contain|allergen|nutrition|'
      r'nutrition facts|nutrition information|serving size|'
      r'energy|calories|protein|carbohydrates?|total fat|fat|sodium)\b',
      caseSensitive: false,
    ).hasMatch(line);
  }

  String _normalizedNumber(String value) => value.replaceAll(',', '.');
}

class LabelOcrParseResult {
  const LabelOcrParseResult({
    this.productName,
    this.servingSizeG,
    this.nutritionBasis,
    this.energyKcal,
    this.proteinG,
    this.carbohydratesG,
    this.totalFatG,
    this.sodiumMg,
    this.ingredients,
    this.precautionaryStatement,
  });

  final String? productName;
  final String? servingSizeG;
  final String? nutritionBasis;
  final String? energyKcal;
  final String? proteinG;
  final String? carbohydratesG;
  final String? totalFatG;
  final String? sodiumMg;
  final String? ingredients;
  final String? precautionaryStatement;

  int get detectedFieldCount => [
    productName,
    servingSizeG,
    energyKcal,
    proteinG,
    carbohydratesG,
    totalFatG,
    sodiumMg,
    ingredients,
    precautionaryStatement,
  ].where((value) => value != null && value.isNotEmpty).length;
}
