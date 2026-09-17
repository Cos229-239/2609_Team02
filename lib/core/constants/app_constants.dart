/// App-wide constants: copy, spacing, sizing and timing values shared
/// across features. Keeping these in one place avoids "magic numbers"
/// scattered through the UI code.
class AppConstants {
  AppConstants._();

  // Branding / copy
  static const String appName = 'Famotive';
  static const String appTagline = 'Together. Support. Grow.';

  // Password-reset / email-action deep linking (Firebase Auth).
  //
  // Firebase Dynamic Links (the service Firebase used to recommend for
  // this) was shut down in Aug 2025. Its replacement routes email-action
  // links (password reset, etc.) through a Firebase Hosting domain using
  // standard Android App Links / iOS Universal Links instead. `famotive.org`
  // must be connected as this Firebase project's Hosting custom domain and
  // listed under Authentication > Settings > Authorized domains — see
  // docs/password-reset-setup.md for the full console checklist.
  static const String authLinkDomain = 'famotive.org';

  // "Continue" link shown after a web-based reset fallback (used only
  // when the email link is opened on a device without the app installed
  // / App Links not yet verified). Doesn't need to be a real page for the
  // in-app flow to work.
  static const String passwordResetContinueUrl =
      'https://famotive.org/reset-password-complete';

  // Must exactly match the applicationId (android/app/build.gradle) /
  // PRODUCT_BUNDLE_IDENTIFIER (iOS) *and* the app registered for those
  // identifiers in the Firebase console.
  //
  // iOS is set to the real bundle ID (Team ID 7R67F8H655 / App ID Prefix,
  // still needs to be added to the iOS app's settings in the Firebase
  // console — see docs/password-reset-setup.md). The Firebase project's
  // iOS app is still registered under the old "com.example.famotive"
  // bundle ID (see lib/firebase_options.dart), so it needs either a new
  // iOS app added for com.famotive or `flutterfire configure` re-run
  // once that's done, or App Links verification for this bundle ID
  // won't work.
  //
  // Android's applicationId/namespace (android/app/build.gradle.kts) and
  // MainActivity's package now match this. The Firebase project's Android
  // app is still registered under the old "com.example.famotive" package
  // (see android/app/google-services.json), so Firebase Auth/Google
  // Sign-In on Android will break until a new Android app is added for
  // com.famotive in the Firebase console and its google-services.json
  // replaces the current one (or `flutterfire configure` is re-run).
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

  // Emoji/glyph text scale used for decorative/avatar Text() icons
  // (e.g. '🔑', '🏆', avatarEmoji, reward.icon). Not a strict geometric
  // scale — sizes were tuned per-screen; centralizing them here still
  // avoids scattering literals and makes future re-tuning a one-line
  // change instead of a repo-wide search.
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
