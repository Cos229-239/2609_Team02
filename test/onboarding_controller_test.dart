import 'package:famotive/core/models/user.dart';
import 'package:famotive/features/onboarding/onboarding_content.dart';
import 'package:famotive/features/onboarding/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _parent = AppUser(id: 'p1', name: 'Pat', email: 'pat@example.com', role: UserRole.parent, householdId: 'h1');
const _child = AppUser(id: 'c1', name: 'Kit', email: 'kit@example.com', role: UserRole.child, householdId: 'h1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new user should see the walkthrough once loaded', () async {
    final controller = OnboardingController();
    expect(controller.shouldAutoStart(_parent), isFalse, reason: 'not loaded yet');
    await controller.load();
    expect(controller.shouldAutoStart(_parent), isTrue);
    expect(controller.isWalkthroughDone(_parent.id), isFalse);
  });

  test('completion persists across app sessions', () async {
    final first = OnboardingController();
    await first.load();
    await first.completeWalkthrough(_parent.id, skipped: false);

    // A new controller = the app was restarted.
    final second = OnboardingController();
    await second.load();
    expect(second.isWalkthroughDone(_parent.id), isTrue);
    expect(second.wasWalkthroughSkipped(_parent.id), isFalse);
    expect(second.shouldAutoStart(_parent), isFalse);
    // Completion is per user.
    expect(second.shouldAutoStart(_child), isTrue);
  });

  test('skipping counts as done but is remembered as skipped', () async {
    final controller = OnboardingController();
    await controller.load();
    await controller.completeWalkthrough(_child.id, skipped: true);
    expect(controller.shouldAutoStart(_child), isFalse);
    expect(controller.wasWalkthroughSkipped(_child.id), isTrue);
  });

  test('step progress is saved, restored and clamped', () async {
    final guide = OnboardingGuides.walkthroughFor(UserRole.child);
    final first = OnboardingController();
    await first.load();
    await first.saveStep(_child.id, guide.id, 3);

    final second = OnboardingController();
    await second.load();
    expect(second.savedStep(_child.id, guide), 3);

    await second.saveStep(_child.id, guide.id, 99);
    expect(second.savedStep(_child.id, guide), guide.steps.length - 1);
  });

  test('resetWalkthrough starts over', () async {
    final controller = OnboardingController();
    await controller.load();
    final guide = OnboardingGuides.walkthroughFor(_parent.role);
    await controller.saveStep(_parent.id, guide.id, 4);
    await controller.completeWalkthrough(_parent.id, skipped: true);

    await controller.resetWalkthrough(_parent);
    expect(controller.isWalkthroughDone(_parent.id), isFalse);
    expect(controller.savedStep(_parent.id, guide), 0);
    expect(controller.shouldAutoStart(_parent), isTrue);
  });

  test('topic guides track completion separately', () async {
    final controller = OnboardingController();
    await controller.load();
    await controller.saveStep(_parent.id, OnboardingGuideId.taskCreation, 2);
    await controller.markGuideDone(_parent.id, OnboardingGuideId.taskCreation);
    expect(controller.isGuideDone(_parent.id, OnboardingGuideId.taskCreation), isTrue);
    expect(controller.savedStep(_parent.id, OnboardingGuides.taskCreation), 0);
    expect(controller.isWalkthroughDone(_parent.id), isFalse);
  });

  test('a tour request is consumed exactly once', () async {
    final controller = OnboardingController();
    expect(controller.consumeTourRequest(), isFalse);
    controller.requestTour();
    expect(controller.consumeTourRequest(), isTrue);
    expect(controller.consumeTourRequest(), isFalse);
  });

  test('works without the preferences plugin (in-memory only)', () async {
    // No load(): nothing is persisted, but the API still behaves.
    final controller = OnboardingController();
    await controller.completeWalkthrough(_parent.id, skipped: false);
    expect(controller.isWalkthroughDone(_parent.id), isTrue);
  });

  test('every guide has steps and role-appropriate topics', () {
    for (final id in OnboardingGuideId.values) {
      expect(OnboardingGuides.byId(id).steps, isNotEmpty, reason: id.name);
      expect(OnboardingGuides.byId(id).id, id);
    }
    expect(OnboardingGuides.walkthroughFor(UserRole.parent).isWalkthrough, isTrue);
    expect(OnboardingGuides.walkthroughFor(UserRole.child).isWalkthrough, isTrue);
    expect(OnboardingGuides.topicsFor(UserRole.parent).map((g) => g.id),
        containsAll([OnboardingGuideId.taskCreation, OnboardingGuideId.household, OnboardingGuideId.parentRewards]));
    expect(OnboardingGuides.topicsFor(UserRole.child).every((g) => !g.isWalkthrough), isTrue);
  });
}
