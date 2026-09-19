/// App-wide constants: copy, spacing, sizing and timing values shared
/// across features. Keeping these in one place avoids "magic numbers"
/// scattered through the UI code.
class AppConstants {
  AppConstants._();

  // Branding / copy
  static const String appName = 'Famotive';
  static const String appTagline = 'Together. Support. Grow.';

  // Password-reset / email-action deep linking (Firebase Auth).
  static const String authLinkDomain = 'famotive.org';
  static const String passwordResetContinueUrl =
      'https://famotive.org/reset-password-complete';
  static const String emailChangeContinueUrl =
      'https://famotive.org/email-change-complete';

  // App identifiers
  static const String androidPackageName = 'com.famotive';
  static const String iosBundleId = 'com.famotive';

  // Spacing scale (multiples of 4dp)
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // Iconography scale (multiples of 4dp)
  static const double iconSm = 16;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double iconXl = 40;

  // Emoji/glyph text scale 
  static const double emojiIconXs = 18;
  static const double emojiIconSm = 20;
  static const double emojiIconMd = 22;
  static const double emojiIconLg = 26;
  static const double emojiIconXl = 32;
  static const double emojiIcon2xl = 36;
  static const double emojiIcon3xl = 48;
  static const double emojiIcon4xl = 64;

  // Small bold status/badge label text (task/reward status pills).
  static const double captionFontSize = 12;

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
