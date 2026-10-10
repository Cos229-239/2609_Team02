/// App-wide constants: copy, spacing, sizing and timing values.
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

  // Legal pages on the website (opened in an in-app browser).
  static const String termsUrl = 'https://famotive.org/terms-and-conditions.html';
  static const String privacyUrl = 'https://famotive.org/privacy-policy.html';
  static const String deleteDataUrl = 'https://famotive.org/delete-my-data.html';

  // App identifiers
  static const String androidPackageName = 'com.famotive';
  static const String iosBundleId = 'com.famotive';

  // Google sign-in OAuth clients (Firebase project famotive-8c858). The web
  // client (client_type 3 in android/app/google-services.json) is what
  // Android's ID tokens are issued for; iOS uses its own client
  // (CLIENT_ID in ios/Runner/GoogleService-Info.plist).
  static const String googleServerClientId =
      '451691992012-uvikp2kfa7eloo3hvdodaa71ndm8auk7.apps.googleusercontent.com';
  static const String googleIosClientId =
      '451691992012-82bm4f26sdhveurbgb8tqj41m300vpoq.apps.googleusercontent.com';

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

  // Households
  /// Longest household name the admin can set (also enforced in
  /// firestore.rules when the name changes).
  static const int householdNameMaxLength = 40;

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
  static const int defaultTaskCoins = 10;
  static const int levelUpXpThreshold = 500;

  // Data retention (privacy): every task is deleted this many days after it
  // was created — by the server's daily run, and hidden/swept by the app in
  // the meantime. See `TaskModel.isAgedOut`.
  static const int taskDeleteAfterDays = 60;

  /// Older name for [taskDeleteAfterDays].
  static const int taskArchiveAfterDays = taskDeleteAfterDays;

  // Approved ("done") tasks stay in task lists this many days after they
  // were approved, then drop out of view. See `TaskModel.isStaleDone`.
  static const int doneTaskVisibleDays = 7;

  static const int taskPhotoRetentionDays = 7;

  // Famotive Premium (photo proof). The free trial is the subscription's
  // introductory offer in App Store Connect / Play Console; keep this in step.
  static const int premiumTrialDays = 7;
  static const String appleManageSubscriptionsUrl = 'https://apps.apple.com/account/subscriptions';
  static const String googleManageSubscriptionsUrl = 'https://play.google.com/store/account/subscriptions';
}

/// Store product ids for Famotive Premium (same ids in App Store Connect and
/// Play Console). Keep in sync with PREMIUM_PRODUCT_IDS in
/// functions/src/premium/plan.ts.
class PremiumProducts {
  PremiumProducts._();

  static const String monthly = 'famotive_premium_monthly';
  static const String yearly = 'famotive_premium_yearly';

  static const Set<String> ids = {monthly, yearly};
}
