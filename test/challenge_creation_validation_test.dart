import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:famotive/app/routes.dart';

import 'package:famotive/core/models/goal.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/goals/models/challenge_draft.dart';
import 'package:famotive/features/goals/screens/review_challenge_screen.dart';

void main() {
  testWidgets('XP target accepts digits but rejects letters', (tester) async {
    final db = DatabaseService(firestore: FakeFirebaseFirestore());

    final draft = ChallengeDraft(
      title: 'Earn 500 XP',
      type: GoalType.family,
      metric: GoalMetric.xpEarned,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(home: ReviewChallengeScreen(draft: draft)),
      ),
    );

    final targetField = find.byType(TextFormField);

    expect(targetField, findsOneWidget);
    expect(find.text('Target XP'), findsOneWidget);

    final textField = tester.widget<TextField>(
      find.descendant(of: targetField, matching: find.byType(TextField)),
    );

    expect(
      textField.inputFormatters!.whereType<FilteringTextInputFormatter>(),
      isNotEmpty,
    );

    await tester.enterText(targetField, 'abc500xyz');
    await tester.pump();

    expect(find.text('500'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });

  testWidgets('empty XP target cannot be submitted', (tester) async {
    final db = DatabaseService(firestore: FakeFirebaseFirestore());

    final draft = ChallengeDraft(
      title: 'Earn 500 XP',
      type: GoalType.family,
      metric: GoalMetric.xpEarned,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(home: ReviewChallengeScreen(draft: draft)),
      ),
    );

    expect(find.byType(TextFormField), findsOneWidget);

    await tester.tap(find.text('Create Challenge'));
    await tester.pump();

    expect(
      find.text('Enter a positive whole number for the target.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });

  testWidgets('zero XP target cannot be submitted', (tester) async {
    final db = DatabaseService(firestore: FakeFirebaseFirestore());

    final draft = ChallengeDraft(
      title: 'Earn XP Challenge',
      type: GoalType.family,
      metric: GoalMetric.xpEarned,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(home: ReviewChallengeScreen(draft: draft)),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();

    await tester.tap(find.text('Create Challenge'));
    await tester.pump();

    expect(
      find.text('Enter a positive whole number for the target.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });

  testWidgets('fixed-chore challenge requires selected tasks', (tester) async {
    final db = DatabaseService(firestore: FakeFirebaseFirestore());

    final draft = ChallengeDraft(
      title: 'Family Cleanup Challenge',
      type: GoalType.family,
      metric: GoalMetric.tasksCompleted,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
      selectedTaskIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(home: ReviewChallengeScreen(draft: draft)),
      ),
    );

    expect(find.text('Required Chores'), findsOneWidget);
    expect(find.text('No chores selected or created.'), findsOneWidget);

    await tester.tap(find.text('Create Challenge'));
    await tester.pump();

    expect(
      find.text('Select at least one chore for this challenge.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });

  testWidgets('valid XP target creates a persisted challenge', (tester) async {
    final firestore = FakeFirebaseFirestore();

    await firestore.collection('households').doc('household-1').set({
      'name': 'Test Household',
      'ownerId': 'parent-1',
      'memberIds': ['parent-1', 'child-1'],
      'timezone': 'America/New_York',
    });

    final db = DatabaseService(firestore: firestore);
    db.bindHousehold('household-1');

    final draft = ChallengeDraft(
      title: 'Earn 500 XP',
      type: GoalType.family,
      metric: GoalMetric.xpEarned,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(
          home: ReviewChallengeScreen(draft: draft),
          routes: {
            AppRoutes.home: (context) =>
                const Scaffold(body: Center(child: Text('Mock Parent Home'))),
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '500');
    await tester.pump();

    await tester.tap(find.text('Create Challenge'));
    await tester.pump();

    // Allow the asynchronous Firestore transaction to complete.
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20; attempt++) {
        final goals = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .get();

        if (goals.docs.isNotEmpty) return;

        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    final savedGoals = await firestore
        .collection('households')
        .doc('household-1')
        .collection('goals')
        .get();

    expect(savedGoals.docs, hasLength(1));
    expect(savedGoals.docs.single.data()['title'], 'Earn 500 XP');
    expect(savedGoals.docs.single.data()['targetValue'], 500);
    expect(savedGoals.docs.single.data()['metric'], GoalMetric.xpEarned.name);
    // Allow navigation to complete after successful challenge creation.
    await tester.pumpAndSettle();

    // Verify the parent is redirected to Home.
    expect(find.text('Mock Parent Home'), findsOneWidget);

    // Verify the challenge review screen is no longer in the widget tree.
    expect(find.byType(ReviewChallengeScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });

  testWidgets('coin target rejects zero and displays validation feedback', (
    tester,
  ) async {
    final db = DatabaseService(firestore: FakeFirebaseFirestore());

    final draft = ChallengeDraft(
      title: 'Earn 200 Coins',
      type: GoalType.family,
      metric: GoalMetric.coinsEarned,
      targetValue: 0,
      period: GoalPeriod.weekly,
      participantIds: const [],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: db,
        child: MaterialApp(home: ReviewChallengeScreen(draft: draft)),
      ),
    );

    expect(find.text('Target Coins'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();

    await tester.tap(find.text('Create Challenge'));
    await tester.pump();

    expect(
      find.text('Enter a positive whole number for the target.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
  });
}
