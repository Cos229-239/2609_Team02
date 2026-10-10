import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide light/dark mode, toggled from Settings and remembered on this
/// device (it applies before sign-in too, so it isn't tied to an account).
///
/// Defaults to light mode, matching the app before dark mode existed;
/// [ThemeMode.system] is supported so a "match my phone" option can be
/// offered as well.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initialMode = ThemeMode.light}) : _mode = initialMode;

  static const String prefsKey = 'appearance.themeMode';

  ThemeMode _mode;
  SharedPreferences? _prefs;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    // load()/saves finish asynchronously and may outlive the provider.
    if (!_disposed) super.notifyListeners();
  }

  ThemeMode get mode => _mode;

  /// The controller provided above [context], or null (e.g. in widget tests
  /// that pump a single screen without the app's providers).
  static ThemeController? maybeOf(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<ThemeController>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Whether the app is currently drawn dark (resolving
  /// [ThemeMode.system] against the device setting).
  bool isDark(BuildContext context) {
    switch (_mode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  /// Restores the saved mode. Safe to call when the preferences plugin is
  /// unavailable (tests): it just keeps the default.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs!.getString(prefsKey);
      final restored = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (restored != null && restored != _mode) {
        _mode = restored;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ThemeController: could not load saved theme ($e)');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(prefsKey, mode.name);
    } catch (e) {
      debugPrint('ThemeController: could not save theme ($e)');
    }
  }

  /// The Settings "Dark Mode" switch.
  Future<void> setDark(bool dark) => setMode(dark ? ThemeMode.dark : ThemeMode.light);
}
