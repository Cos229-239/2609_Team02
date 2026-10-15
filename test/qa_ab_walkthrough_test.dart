import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:famotive/app/app.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/qa/ab_walkthrough_main.dart';
import 'package:famotive/qa/demo_family.dart';
import 'package:famotive/qa/walkthrough_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _settingsTooltip = 'Settings: account, dark mode, app tour and help';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'qa.abWalkthrough.variant': 'B'}));

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Scrolls the setup + results screen until [finder] is built.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  /// In the demo app: Settings tab, then "End test".
  Future<void> endTest(WidgetTester tester) async {
    expect(find.byType(FamotiveApp), findsOneWidget);
    await tester.tap(find.byTooltip(_settingsTooltip).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('demo-end-test')));
    await tester.pumpAndSettle();
    expect(find.text('Log Out'), findsNothing);
    await tester.tap(find.byKey(const Key('demo-end-test')));
    await tester.pumpAndSettle();
    expect(find.byType(FamotiveApp), findsNothing);
  }

  test('B is shorter than A for both roles', () {
    for (final role in UserRole.values) {
      expect(WalkthroughVariant.b.guideFor(role).steps.length, 4);
      expect(WalkthroughVariant.a.guideFor(role).steps.length,
          greaterThan(WalkthroughVariant.b.guideFor(role).steps.length));
    }
  });

  test('demo family seeds a household with tasks and rewards', () async {
    final firestore = FakeFirebaseFirestore();
    await DemoFamily.seed(firestore, now: DateTime(2026, 10, 15, 12));
    final household = firestore.collection('households').doc(DemoFamily.householdId);
    expect((await household.get()).data()!['memberIds'], hasLength(3));
    expect((await household.collection('tasks').get()).docs, isNotEmpty);
    expect((await household.collection('rewards').get()).docs, isNotEmpty);

    final session = await DemoSession.start(UserRole.child);
    expect(session.authService.currentUser?.id, DemoFamily.maya.id);
  });

  testWidgets('opens straight into a random version, then the demo app, then the survey', (tester) async {
    bigScreen(tester);
    // nextBool() answers: variant B, then role child.
    await tester.pumpWidget(AbWalkthroughApp(queryParameters: const {}, random: _ScriptedRandom([false, false])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qa-start')), findsNothing);
    expect(find.byKey(const Key('onboarding-next')), findsOneWidget);
    expect(find.text('VERSION B'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    // The whole app, signed in as the demo child, still watermarked.
    expect(find.text('VERSION B'), findsOneWidget);
    await endTest(tester);

    expect(find.text('VERSION B'), findsNothing);
    expect(find.textContaining('You tested VERSION B as a child'), findsOneWidget);
    expect(find.byKey(const Key('qa-again')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-show-results')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('step 1/4'));
    expect(find.text('3. Runs (1)'), findsOneWidget);
    expect(find.textContaining('step 1/4'), findsOneWidget);
  });

  testWidgets('setup mode: pick a variant by hand, go one step, skip, end test', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(const AbWalkthroughApp(queryParameters: {'setup': '1'}));
    await tester.pumpAndSettle();
    expect(find.text('Start walkthrough (4 steps)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    await endTest(tester);

    await scrollTo(tester, find.textContaining('Skipped · step 2/4'));
    expect(find.text('3. Runs (1)'), findsOneWidget);
  });

  testWidgets('survey button is enabled once a survey link is set', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(const AbWalkthroughApp(queryParameters: {
      'variant': 'a',
      'role': 'parent',
      'survey': 'https://example.com/form?v={version}&r={role}&run={run}',
    }));
    await tester.pumpAndSettle();
    expect(find.text('VERSION A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    await endTest(tester);

    final button = tester.widget<ElevatedButton>(find.byKey(const Key('qa-survey')));
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('You tested VERSION A as a parent'), findsOneWidget);
  });
}

/// Returns scripted nextBool() values (variant pick first, then role pick).
class _ScriptedRandom implements math.Random {
  _ScriptedRandom(this._bools);

  final List<bool> _bools;
  var _i = 0;

  @override
  bool nextBool() => _bools[_i++ % _bools.length];

  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0;
}
