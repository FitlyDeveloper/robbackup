// Helper functions for formatting nutrition values
class NutritionFormatters {
  // Format calories as "204 kcal"
  static String formatKcal(double v) => '${v.round()} kcal';
  
  // Format grams with 1 decimal place as "5.2g"
  static String g1(num v) => '${v.toStringAsFixed(1)}g';
  
  // Format grams as integer as "5g"
  static String g0(num v) => '${v.round()}g';
  
  // Format percentage as "65%"
  static String percent(num v) => '${v.round()}%';
  
  // Format micrograms as "585 mcg"
  static String mcg(num v) => '${v.round()} mcg';
  
  // Format milligrams as "16.6 mg"
  static String mg(num v) => '${v.toStringAsFixed(1)} mg';
}
