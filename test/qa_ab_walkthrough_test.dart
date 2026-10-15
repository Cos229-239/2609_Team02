import 'package:famotive/core/models/user.dart';
import 'package:famotive/qa/ab_walkthrough_main.dart';
import 'package:famotive/qa/walkthrough_variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'qa.abWalkthrough.variant': 'B'}));

  test('B is shorter than A for both roles', () {
    for (final role in UserRole.values) {
      expect(WalkthroughVariant.b.guideFor(role).steps.length, 4);
      expect(WalkthroughVariant.a.guideFor(role).steps.length,
          greaterThan(WalkthroughVariant.b.guideFor(role).steps.length));
    }
  });

  testWidgets('runs variant B to the end and records the result', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AbWalkthroughApp());
    await tester.pumpAndSettle();
    expect(find.text('Start walkthrough (4 steps)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qa-start')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('onboarding-tour')));
    await tester.pumpAndSettle();

    expect(find.text('Finished → tour'), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-clarity-5')));
    await tester.tap(find.byKey(const Key('qa-save')));
    await tester.pumpAndSettle();

    expect(find.text('3. Runs (1)'), findsOneWidget);
    expect(find.textContaining('step 4/4'), findsOneWidget);
    expect(find.textContaining('clarity 5/5'), findsOneWidget);
  });

  testWidgets('records a skip', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AbWalkthroughApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qa-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Skipped')), findsOneWidget);
    await tester.tap(find.byKey(const Key('qa-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('step 2/4'), findsOneWidget);
  });
}
