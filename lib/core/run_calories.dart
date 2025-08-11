class RunCalories {
  // Very simple kcal estimate: MET 9.8 running ~1.63 kcal/kg/km at 10 km/h.
  // We expose a compute with distance (km), duration (min), and optional weight (kg).
  static int compute({required double distanceKm, required int minutes, double? weightKg}) {
    // Fallback: estimate kcal ~ 60 kcal per km for average 70 kg runner
    final double basePerKm = (weightKg != null && weightKg > 0)
        ? 1.0 * weightKg // 1 kcal/kg/km approximation
        : 60.0; // default
    final double kcal = distanceKm * basePerKm;
    return kcal.round();
  }
}


