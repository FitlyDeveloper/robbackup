enum IntensityLevel {
  extremelyLight, // 1
  light,          // 2
  moderate,       // 3
  difficult,      // 4
  veryDifficult,  // 5
  maximumEffort,  // 6
}

extension IntensityLevelX on IntensityLevel {
  int get rank => index + 1; // 1..6
  String get label {
    switch (this) {
      case IntensityLevel.extremelyLight: return 'Extremely light';
      case IntensityLevel.light:          return 'Light';
      case IntensityLevel.moderate:       return 'Moderate';
      case IntensityLevel.difficult:      return 'Difficult';
      case IntensityLevel.veryDifficult:  return 'Very difficult';
      case IntensityLevel.maximumEffort:  return 'Maximum effort';
    }
  }
}



