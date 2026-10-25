import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/core/models/goal.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/goals/screens/goals_screen.dart';

void main() {
  testWidgets('parent sees an active challenge and its progress', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'parent-1',
        email: 'parent@test.com',
        displayName: 'Test Parent',
      ),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('parent-1')
        .set(
          const AppUser(
            id: 'parent-1',
            name: 'Test Parent',
            email: 'parent@test.com',
            role: UserRole.parent,
            householdId: 'household-1',
          ).toFirestore(),
        );

    final authService = AuthService(auth: mockAuth, firestore: firestore);

    await authService.tryRestoreSession();

    final db = DatabaseService(firestore: firestore);

    final now = DateTime.now();

    db.goals = [
      Goal(
        id: 'goal-1',
        title: 'Kitchen Cleanup Week',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        currentProgress: 3,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 1)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Family Challenges & Goals'), findsOneWidget);

    expect(find.text('Kitchen Cleanup Week'), findsOneWidget);

    expect(find.text('3 / 5 tasks'), findsOneWidget);

    expect(find.text('No completed challenges yet.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });

  testWidgets('child sees only relevant household challenges', (tester) async {
    final firestore = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      ),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('child-1')
        .set(
          const AppUser(
            id: 'child-1',
            name: 'Test Child',
            email: 'child@test.com',
            role: UserRole.child,
            householdId: 'household-1',
          ).toFirestore(),
        );

    final authService = AuthService(auth: mockAuth, firestore: firestore);

    await authService.tryRestoreSession();

    final db = DatabaseService(firestore: firestore);
    final now = DateTime.now();

    Goal makeGoal({
      required String id,
      required String title,
      required GoalType type,
      List<String> participantIds = const [],
    }) {
      return Goal(
        id: id,
        title: title,
        type: type,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: participantIds,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 1)),
      );
    }

    db.goals = [
      makeGoal(id: 'family-1', title: 'Family Cleanup', type: GoalType.family),
      makeGoal(
        id: 'individual-1',
        title: 'My Reading Goal',
        type: GoalType.individual,
        participantIds: ['child-1'],
      ),
      makeGoal(
        id: 'individual-2',
        title: 'Sibling Reading Goal',
        type: GoalType.individual,
        participantIds: ['child-2'],
      ),
      makeGoal(
        id: 'team-1',
        title: 'Sibling Team Challenge',
        type: GoalType.team,
        participantIds: ['child-2', 'child-3'],
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Family Cleanup'), findsOneWidget);
    expect(find.text('My Reading Goal'), findsOneWidget);

    expect(find.text('Sibling Reading Goal'), findsNothing);
    expect(find.text('Sibling Team Challenge'), findsNothing);
    expect(find.text('Create Challenge'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });

  testWidgets('completed challenge appears in completed section', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'parent-1',
        email: 'parent@test.com',
        displayName: 'Test Parent',
      ),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('parent-1')
        .set(
          const AppUser(
            id: 'parent-1',
            name: 'Test Parent',
            email: 'parent@test.com',
            role: UserRole.parent,
            householdId: 'household-1',
          ).toFirestore(),
        );

    final authService = AuthService(auth: mockAuth, firestore: firestore);

    await authService.tryRestoreSession();

    final db = DatabaseService(firestore: firestore);
    final now = DateTime.now();

    db.goals = [
      Goal(
        id: 'completed-goal',
        title: 'Completed Kitchen Challenge',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        currentProgress: 5,
        startsAt: now.subtract(const Duration(days: 2)),
        endsAt: now.add(const Duration(days: 2)),
        completedAt: now.subtract(const Duration(hours: 1)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('No active challenges right now.'), findsOneWidget);
    expect(find.text('Completed Kitchen Challenge'), findsOneWidget);
    expect(find.text('5 / 5 tasks'), findsOneWidget);
    expect(find.text('No completed challenges yet.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });

  testWidgets('future challenge appears in Scheduled Challenges', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'parent-1',
        email: 'parent@test.com',
        displayName: 'Test Parent',
      ),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('parent-1')
        .set(
          const AppUser(
            id: 'parent-1',
            name: 'Test Parent',
            email: 'parent@test.com',
            role: UserRole.parent,
            householdId: 'household-1',
          ).toFirestore(),
        );

    final authService = AuthService(auth: mockAuth, firestore: firestore);

    await authService.tryRestoreSession();

    final db = DatabaseService(firestore: firestore);
    final now = DateTime.now();

    db.goals = [
      Goal(
        id: 'scheduled-goal',
        title: 'Weekend Family Cleanup',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        startsAt: now.add(const Duration(days: 2)),
        endsAt: now.add(const Duration(days: 9)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Scheduled Challenges'), findsOneWidget);
    expect(find.text('Weekend Family Cleanup'), findsOneWidget);
    expect(find.text('No active challenges right now.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });

  testWidgets('expired incomplete challenge appears in Past Challenges', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    final mockAuth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'parent-1',
        email: 'parent@test.com',
        displayName: 'Test Parent',
      ),
      signedIn: true,
    );

    await firestore
        .collection('users')
        .doc('parent-1')
        .set(
          const AppUser(
            id: 'parent-1',
            name: 'Test Parent',
            email: 'parent@test.com',
            role: UserRole.parent,
            householdId: 'household-1',
          ).toFirestore(),
        );

    final authService = AuthService(auth: mockAuth, firestore: firestore);

    await authService.tryRestoreSession();

    final db = DatabaseService(firestore: firestore);
    final now = DateTime.now();

    db.goals = [
      Goal(
        id: 'expired-goal',
        title: 'Last Week Cleanup',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        currentProgress: 3,
        startsAt: now.subtract(const Duration(days: 9)),
        endsAt: now.subtract(const Duration(days: 2)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: const MaterialApp(home: GoalsScreen()),
      ),
    );

    await tester.pump();

    expect(find.text('Past Challenges'), findsOneWidget);
    expect(find.text('Last Week Cleanup'), findsOneWidget);
    expect(find.text('3 / 5 tasks'), findsOneWidget);
    expect(find.text('No active challenges right now.'), findsOneWidget);
    expect(find.text('No completed challenges yet.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });
}
