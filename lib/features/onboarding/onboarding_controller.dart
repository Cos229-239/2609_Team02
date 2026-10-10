import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/user.dart';
import 'onboarding_content.dart';

/// Remembers, per signed-in user and on this device, how far they've got
/// through each onboarding guide and whether the first-time walkthrough is
/// finished (or was skipped) so returning users aren't prompted again.
///
/// Everything is cached in memory and written through to
/// [SharedPreferences]; if the plugin isn't available (widget tests) the
/// controller still works, it just doesn't survive a restart.
class OnboardingController extends ChangeNotifier {
  OnboardingController();

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
  bool _loaded = false;
  final Map<String, Object> _cache = {};
  bool _tourRequested = false;

  /// True once [load] has finished (successfully or not).
  bool get isLoaded => _loaded;

  /// The controller provided above [context], or null when there isn't one
  /// (e.g. widget tests that pump a single screen).
  static OnboardingController? maybeOf(BuildContext context, {bool listen = false}) {
    try {
      return Provider.of<OnboardingController>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      for (final key in _prefs!.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final value = _prefs!.get(key);
        if (value is bool || value is int) _cache[key] = value!;
      }
    } catch (e) {
      debugPrint('OnboardingController: could not load saved progress ($e)');
    }
    _loaded = true;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // First-time walkthrough
  // -------------------------------------------------------------------

  /// Whether [user] has finished or skipped their role's walkthrough.
  bool isWalkthroughDone(String userId) => _cache[_doneKey(userId)] == true;

  /// Whether the walkthrough was dismissed with "Skip" (vs. finished).
  bool wasWalkthroughSkipped(String userId) => _cache[_skippedKey(userId)] == true;

  /// Whether to auto-launch the walkthrough for [user] right now.
  bool shouldAutoStart(AppUser user) => _loaded && !isWalkthroughDone(user.id);

  /// Marks the walkthrough finished ([skipped] = false) or skipped.
  Future<void> completeWalkthrough(String userId, {required bool skipped}) async {
    await _write(_doneKey(userId), true);
    await _write(_skippedKey(userId), skipped);
    notifyListeners();
  }

  /// "Restart walkthrough": forget completion and progress so it starts
  /// again from step 1 (and would auto-launch again next time).
  Future<void> resetWalkthrough(AppUser user) async {
    await _write(_doneKey(user.id), false);
    await _write(_skippedKey(user.id), false);
    await _write(_stepKey(user.id, OnboardingGuides.walkthroughFor(user.role).id), 0);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Per-guide progress (resume where you left off)
  // -------------------------------------------------------------------

  /// The step index to resume [guide] at (0 when never started).
  int savedStep(String userId, OnboardingGuide guide) {
    final step = _cache[_stepKey(userId, guide.id)];
    if (step is! int || step < 0) return 0;
    final last = guide.steps.length - 1;
    return step > last ? last : step;
  }

  Future<void> saveStep(String userId, OnboardingGuideId guideId, int step) async {
    if (_cache[_stepKey(userId, guideId)] == step) return;
    await _write(_stepKey(userId, guideId), step);
    notifyListeners();
  }

  /// Whether [guideId] has been read to the end at least once.
  bool isGuideDone(String userId, OnboardingGuideId guideId) =>
      _cache[_guideDoneKey(userId, guideId)] == true;

  Future<void> markGuideDone(String userId, OnboardingGuideId guideId) async {
    await _write(_guideDoneKey(userId, guideId), true);
    // Next time it's opened it starts from the top again.
    await _write(_stepKey(userId, guideId), 0);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Spotlight tour hand-off
  // -------------------------------------------------------------------

  /// Asks the main tab shell to run its spotlight ("Show me around") tour
  /// as soon as it's back on screen.
  void requestTour() {
    _tourRequested = true;
    notifyListeners();
  }

  /// Returns true (once) if a tour was requested. Doesn't notify.
  bool consumeTourRequest() {
    if (!_tourRequested) return false;
    _tourRequested = false;
    return true;
  }

  // -------------------------------------------------------------------

  static const _prefix = 'onboarding.';
  static String _doneKey(String uid) => '$_prefix$uid.walkthroughDone';
  static String _skippedKey(String uid) => '$_prefix$uid.walkthroughSkipped';
  static String _stepKey(String uid, OnboardingGuideId id) => '$_prefix$uid.step.${id.name}';
  static String _guideDoneKey(String uid, OnboardingGuideId id) => '$_prefix$uid.done.${id.name}';

  Future<void> _write(String key, Object value) async {
    _cache[key] = value;
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      }
    } catch (e) {
      debugPrint('OnboardingController: could not save $key ($e)');
    }
  }
}
