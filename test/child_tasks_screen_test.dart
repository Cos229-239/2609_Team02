import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/screens/child_tasks_screen.dart';

void main() {
  group('ChildTasksScreen task status regression tests', () {
    testWidgets('completed child task displays as awaiting approval', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'task-awaiting',
          title: 'Clean Bedroom',
          assignedToUserId: 'child-1',
          rewardXp: 25,
          status: TaskStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      // Awaiting Approval starts closed; open it.
      await tester.tap(find.text('Awaiting Approval'));
      await tester.pumpAndSettle();

      expect(find.text('Clean Bedroom'), findsOneWidget);

      expect(find.text('Awaiting Approval'), findsNWidgets(2));

      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('approved child task displays as approved', (tester) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'task-approved',
          title: 'Take Out Trash',
          assignedToUserId: 'child-1',
          rewardXp: 25,
          status: TaskStatus.approved,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Completed'));
      await tester.pump();

      expect(find.text('Take Out Trash'), findsOneWidget);

      expect(find.text('Approved'), findsOneWidget);

      expect(find.text('Awaiting Approval'), findsNothing);
    });

    testWidgets('completed child task appears in awaiting approval section', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'task-awaiting',
          title: 'Piano Lessons',
          assignedToUserId: 'child-1',
          rewardXp: 200,
          status: TaskStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      // Closed drawer: only the header, not the task.
      expect(find.text('Awaiting Approval'), findsOneWidget);
      expect(find.text('Piano Lessons'), findsNothing);

      await tester.tap(find.text('Awaiting Approval'));
      await tester.pumpAndSettle();

      expect(find.text('Awaiting Approval'), findsNWidgets(2));

      expect(find.text('Piano Lessons'), findsOneWidget);
    });

    testWidgets('awaiting approval task does not appear in completed history', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'task-awaiting',
          title: 'Piano Lessons',
          assignedToUserId: 'child-1',
          rewardXp: 200,
          status: TaskStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      await tester.tap(find.text('Completed'));
      await tester.pump();

      expect(find.text('Piano Lessons'), findsNothing);
    });

    testWidgets('challenge-linked child task displays Challenge badge', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'challenge-task',
          title: 'Wash Dishes',
          assignedToUserId: 'child-1',
          rewardXp: 25,
          status: TaskStatus.pending,
          goalId: 'goal-1',
        ),
        const TaskModel(
          id: 'regular-task',
          title: 'Make Bed',
          assignedToUserId: 'child-1',
          rewardXp: 10,
          status: TaskStatus.pending,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      expect(find.text('Wash Dishes'), findsOneWidget);
      expect(find.text('Make Bed'), findsOneWidget);

      // Only the challenge-linked task receives a badge.
      expect(find.text('Challenge'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);

      // The badge uses the challenge accent color.
      final badgeText = tester.widget<Text>(find.text('Challenge'));
      expect(badgeText.style?.color, Colors.amber);
      // Find the outer task card containing the challenge task title.
      final challengeCard = find
          .ancestor(
            of: find.text('Wash Dishes'),
            matching: find.byType(Container),
          )
          .first;

      final challengeContainer = tester.widget<Container>(challengeCard);
      final challengeDecoration =
          challengeContainer.decoration as BoxDecoration;
      final challengeBorder = challengeDecoration.border as Border;

      expect(challengeBorder.top.color, Colors.amber);
      expect(challengeBorder.top.width, 2);

      // Regular tasks retain the standard border width.
      final regularCard = find
          .ancestor(of: find.text('Make Bed'), matching: find.byType(Container))
          .first;

      final regularContainer = tester.widget<Container>(regularCard);
      final regularDecoration = regularContainer.decoration as BoxDecoration;
      final regularBorder = regularDecoration.border as Border;

      expect(regularBorder.top.width, 1);
      expect(regularBorder.top.color, isNot(Colors.amber));
    });

    testWidgets('completed challenge task retains badge awaiting approval', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'completed-challenge-task',
          title: 'Clean Kitchen',
          assignedToUserId: 'child-1',
          rewardXp: 25,
          status: TaskStatus.completed,
          goalId: 'goal-1',
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      // The task is initially hidden in the collapsed section.
      expect(find.text('Clean Kitchen'), findsNothing);

      await tester.tap(find.text('Awaiting Approval'));
      await tester.pumpAndSettle();

      expect(find.text('Clean Kitchen'), findsOneWidget);
      expect(find.text('Challenge'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
    });

    testWidgets('approved challenge task retains badge in Completed', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();

      final mockUser = MockUser(
        uid: 'child-1',
        email: 'child@test.com',
        displayName: 'Test Child',
      );

      final mockAuth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

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

      final databaseService = DatabaseService(firestore: firestore);

      databaseService.tasks = [
        const TaskModel(
          id: 'approved-challenge-task',
          title: 'Clean Bathroom',
          assignedToUserId: 'child-1',
          rewardXp: 25,
          status: TaskStatus.approved,
          goalId: 'goal-1',
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<DatabaseService>.value(
              value: databaseService,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildTasksScreen())),
        ),
      );

      await tester.pump();

      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.text('Clean Bathroom'), findsOneWidget);
      expect(find.text('Challenge'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      // Approved challenge tasks retain their gold card border.
      final challengeCard = find
          .ancestor(
            of: find.text('Clean Bathroom'),
            matching: find.byType(Container),
          )
          .first;

      final challengeContainer = tester.widget<Container>(challengeCard);
      final decoration = challengeContainer.decoration as BoxDecoration;
      final border = decoration.border as Border;

      expect(border.top.color, Colors.amber);
      expect(border.top.width, 2);
    });
  });
}
