import 'package:famotive/core/models/user.dart';
import 'package:famotive/features/onboarding/onboarding_content.dart';
import 'package:famotive/features/onboarding/onboarding_controller.dart';
import 'package:famotive/features/onboarding/screens/onboarding_screen.dart';
import 'package:famotive/shared/widgets/help_tip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kidId = 'kid-1';

Widget _host(OnboardingController controller, OnboardingGuide guide, {bool resume = true}) {
  return ChangeNotifierProvider<OnboardingController>.value(
    value: controller,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => OnboardingScreen.open(context, guide: guide, userId: _kidId, resume: resume),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<OnboardingController> _loadedController(WidgetTester tester) async {
  final controller = OnboardingController();
  await tester.runAsync(controller.load);
  return controller;
}

void main() {
  final guide = OnboardingGuides.walkthroughFor(UserRole.child);
  final total = guide.steps.length;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('moves forward and back between steps and saves progress', (tester) async {
    final controller = await _loadedController(tester);
    await tester.pumpWidget(_host(controller, guide));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(guide.steps.first.title), findsWidgets);
    expect(find.text('Step 1 of $total'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-back')), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of $total'), findsOneWidget);
    expect(controller.savedStep(_kidId, guide), 1);

    await tester.tap(find.byKey(const Key('onboarding-back')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of $total'), findsOneWidget);
    expect(controller.savedStep(_kidId, guide), 0);
  });

  testWidgets('Skip closes the walkthrough and marks it done (skipped)', (tester) async {
    final controller = await _loadedController(tester);
    await tester.pumpWidget(_host(controller, guide));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(controller.isWalkthroughDone(_kidId), isTrue);
    expect(controller.wasWalkthroughSkipped(_kidId), isTrue);

    // Let the "replay any time" snackbar time out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('resumes at the saved step', (tester) async {
    final controller = await _loadedController(tester);
    await tester.runAsync(() => controller.saveStep(_kidId, guide.id, 3));

    await tester.pumpWidget(_host(controller, guide));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of $total'), findsOneWidget);
  });

  testWidgets('restart ignores the saved step', (tester) async {
    final controller = await _loadedController(tester);
    await tester.runAsync(() => controller.saveStep(_kidId, guide.id, 3));

    await tester.pumpWidget(_host(controller, guide, resume: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of $total'), findsOneWidget);
    expect(controller.savedStep(_kidId, guide), 0);
  });

  testWidgets('finishing on the last step completes the walkthrough', (tester) async {
    final controller = await _loadedController(tester);
    await tester.pumpWidget(_host(controller, guide));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (var i = 1; i < total; i++) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Step $total of $total'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-tour')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-finish')));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(controller.isWalkthroughDone(_kidId), isTrue);
    expect(controller.wasWalkthroughSkipped(_kidId), isFalse);
  });

  testWidgets('HelpTip shows its explanation when tapped', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: HelpTip(title: 'Coins', message: 'Spend them in the Reward Store.'),
          ),
        ),
      ),
    );

    expect(find.textContaining('Spend them in the Reward Store.', findRichText: true), findsNothing);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Spend them in the Reward Store.', findRichText: true), findsOneWidget);

    // Auto-hides after a few seconds.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.textContaining('Spend them in the Reward Store.', findRichText: true), findsNothing);
  });
}
