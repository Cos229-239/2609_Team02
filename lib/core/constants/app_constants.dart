/// App-wide constants: copy, spacing, sizing and timing values shared
/// across features. Keeping these in one place avoids "magic numbers"
/// scattered through the UI code.
class AppConstants {
  AppConstants._();

  // Branding / copy
  static const String appName = 'Famotive';
  static const String appTagline = 'Together. Support. Grow.';

  // Spacing scale (multiples of 4dp)
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // Shape
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusPill = 999;

  // Motion
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationMedium = Duration(milliseconds: 300);

  // Gamification defaults (placeholder balancing values)
  static const int defaultTaskXp = 50;
  static const int levelUpXpThreshold = 500;
}
