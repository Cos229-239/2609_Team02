import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-level accessibility preferences (Settings > Accessibility),
/// remembered on this device like the theme (see [ThemeController]).
///
/// [swipeActions]: whether task rows respond to swipe gestures (approve,
/// complete, claim, delete...). Off is for people who swipe by accident
/// or find the gestures hard; every action stays available by tapping
/// the task to open its card.
class AccessibilitySettings extends ChangeNotifier {
  AccessibilitySettings({bool swipeActions = true}) : _swipeActions = swipeActions;

  static const String swipeActionsKey = 'accessibility.swipeActions';

  bool _swipeActions;
  SharedPreferences? _prefs;
  bool _disposed = false;

  bool get swipeActions => _swipeActions;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// The settings provided above [context], or null (widget tests that pump
  /// a single screen without the app's providers).
  static AccessibilitySettings? maybeOf(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<AccessibilitySettings>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Whether swipe gestures are on for task rows (on by default, including
  /// when no settings are provided).
  static bool swipesEnabled(BuildContext context) => maybeOf(context)?.swipeActions ?? true;

  /// Restores saved choices. Safe when the preferences plugin is
  /// unavailable (tests): defaults are kept.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs!.getBool(swipeActionsKey);
      if (saved != null && saved != _swipeActions) {
        _swipeActions = saved;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AccessibilitySettings: could not load ($e)');
    }
  }

  Future<void> setSwipeActions(bool enabled) async {
    if (enabled == _swipeActions) return;
    _swipeActions = enabled;
    notifyListeners();
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(swipeActionsKey, enabled);
    } catch (e) {
      debugPrint('AccessibilitySettings: could not save ($e)');
    }
  }
}
