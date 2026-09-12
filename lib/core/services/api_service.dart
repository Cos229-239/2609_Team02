import '../config/app_config.dart';

/// Thin placeholder wrapper around whatever HTTP client the app ends up
/// using once a real backend exists. Kept dependency-free for now so the
/// project structure is in place without committing to an HTTP package
/// before it's needed.
///
/// [DatabaseService] and [AuthService] currently hold their own mocked,
/// in-memory data; once a backend is available, they can delegate to this
/// class instead.
class ApiService {
  ApiService({AppConfig? config}) : config = config ?? AppConfig.instance;

  final AppConfig config;

  String get baseUrl => config.apiBaseUrl;

  Future<Map<String, dynamic>> get(String path) {
    // TODO: implement once a backend (e.g. Firebase Cloud Functions / REST
    // API) is available. Intentionally throws so accidental use during
    // development is obvious rather than silently no-op-ing.
    throw UnimplementedError(
      'ApiService.get is not implemented yet ($baseUrl$path)',
    );
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) {
    // TODO: implement once a backend is available.
    throw UnimplementedError(
      'ApiService.post is not implemented yet ($baseUrl$path)',
    );
  }
}
