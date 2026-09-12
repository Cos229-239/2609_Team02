/// Simple environment/configuration handling.
///
/// Values are supplied at build/run time via `--dart-define`, e.g.:
///
///   flutter run --dart-define=ENVIRONMENT=staging \
///                --dart-define=API_BASE_URL=https://staging.api.famotive.app
///
/// This keeps secrets and per-environment URLs out of source control while
/// still giving every layer of the app (services, theming, feature flags)
/// a single, typed place to read configuration from.
enum AppEnvironment { dev, staging, prod }

class AppConfig {
  AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.enableAnalytics,
  });

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool enableAnalytics;

  static AppConfig? _instance;

  /// Reads `--dart-define` values (falling back to sane dev defaults) and
  /// caches the result. Call once during app startup, before [instance] is
  /// used anywhere else.
  static AppConfig load() {
    const envName = String.fromEnvironment(
      'ENVIRONMENT',
      defaultValue: 'dev',
    );
    final environment = AppEnvironment.values.firstWhere(
      (e) => e.name == envName,
      orElse: () => AppEnvironment.dev,
    );

    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dev.api.famotive.app',
    );

    const enableAnalytics = bool.fromEnvironment(
      'ENABLE_ANALYTICS',
      defaultValue: false,
    );

    return _instance = AppConfig._(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      enableAnalytics: enableAnalytics,
    );
  }

  static AppConfig get instance => _instance ?? load();

  bool get isProd => environment == AppEnvironment.prod;
  bool get isDev => environment == AppEnvironment.dev;
}
