class IngredientItem {
  final String name;
  final double grams;
  final double caloriesKcal;
  final double proteinG;
  final double fatG;
  final double carbsG;

  IngredientItem({
    required this.name,
    required this.grams,
    required this.caloriesKcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory IngredientItem.fromJson(Map<String, dynamic> j) {
    double d(v) => (v is int) ? v.toDouble() : (v as num?)?.toDouble() ?? 0.0;
    return IngredientItem(
      name: (j['name'] ?? '').toString(),
      grams: d(j['grams']),
      caloriesKcal: d(j['calories_kcal']),
      proteinG: d(j['protein_g']),
      fatG: d(j['fat_g']),
      carbsG: d(j['carbs_g']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'grams': grams,
      'calories_kcal': caloriesKcal,
      'protein_g': proteinG,
      'fat_g': fatG,
      'carbs_g': carbsG,
    };
  }
}

class NutritionResponse {
  final List<IngredientItem> ingredients;
  final Map<String, dynamic> macros;
  final Map<String, dynamic> vitamins;
  final Map<String, dynamic> minerals;
  final Map<String, dynamic> other;
  final Map<String, dynamic> dvPct;
  final String foodName;

  NutritionResponse({
    required this.ingredients,
    required this.macros,
    required this.vitamins,
    required this.minerals,
    required this.other,
    required this.dvPct,
    required this.foodName,
  });

  factory NutritionResponse.fromJson(Map<String, dynamic> j) {
    final list = (j['ingredients'] as List? ?? [])
        .map((e) => IngredientItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // Extract micronutrients from flat format (new API response)
    Map<String, dynamic> vitamins = {};
    Map<String, dynamic> minerals = {};
    Map<String, dynamic> other = {};

    // Process all keys to extract micronutrients
    j.forEach((key, value) {
      if (key.startsWith('vitamin_')) {
        vitamins[key] = value;
      } else if (['calcium', 'chloride', 'chromium', 'copper', 'fluoride', 'iodine', 'iron', 'magnesium', 'manganese', 'molybdenum', 'phosphorus', 'potassium', 'selenium', 'sodium', 'zinc'].contains(key)) {
        minerals[key] = value;
      } else if (['fiber', 'cholesterol', 'sugar', 'saturated_fats', 'omega_3', 'omega_6'].contains(key)) {
        other[key] = value;
      }
    });

    return NutritionResponse(
      ingredients: list,
      macros: j['macros'] as Map<String, dynamic>? ?? {},
      vitamins: vitamins,
      minerals: minerals,
      other: other,
      dvPct: j['dv_pct'] as Map<String, dynamic>? ?? {},
      foodName: (j['food_name'] ?? 'Analyzed Food').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'macros': macros,
      'vitamins': vitamins,
      'minerals': minerals,
      'other': other,
      'dv_pct': dvPct,
      'food_name': foodName,
    };
  }

  bool get isValid {
    return ingredients.isNotEmpty && foodName.isNotEmpty && macros.isNotEmpty;
  }
}
