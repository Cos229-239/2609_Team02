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
    testWidgets(
      'completed child task displays as awaiting approval',
      (tester) async {
        final firestore = FakeFirebaseFirestore();

        final mockUser = MockUser(
          uid: 'child-1',
          email: 'child@test.com',
          displayName: 'Test Child',
        );

        final mockAuth = MockFirebaseAuth(
          mockUser: mockUser,
          signedIn: true,
        );

        await firestore.collection('users').doc('child-1').set(
          const AppUser(
            id: 'child-1',
            name: 'Test Child',
            email: 'child@test.com',
            role: UserRole.child,
            householdId: 'household-1',
          ).toFirestore(),
        );

        final authService = AuthService(
          auth: mockAuth,
          firestore: firestore,
        );

        await authService.tryRestoreSession();

        final databaseService = DatabaseService(
          firestore: firestore,
        );

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
              ChangeNotifierProvider<AuthService>.value(
                value: authService,
              ),
              ChangeNotifierProvider<DatabaseService>.value(
                value: databaseService,
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ChildTasksScreen(),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Clean Bedroom'), findsOneWidget);

        expect(
          find.text('Awaiting Approval'),
          findsOneWidget,
        );

        expect(
          find.text('Completed'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
  'approved child task displays as approved',
  (tester) async {
    final firestore = FakeFirebaseFirestore();

    final mockUser = MockUser(
      uid: 'child-1',
      email: 'child@test.com',
      displayName: 'Test Child',
    );

    final mockAuth = MockFirebaseAuth(
      mockUser: mockUser,
      signedIn: true,
    );

    await firestore.collection('users').doc('child-1').set(
      const AppUser(
        id: 'child-1',
        name: 'Test Child',
        email: 'child@test.com',
        role: UserRole.child,
        householdId: 'household-1',
      ).toFirestore(),
    );

    final authService = AuthService(
      auth: mockAuth,
      firestore: firestore,
    );

    await authService.tryRestoreSession();

    final databaseService = DatabaseService(
      firestore: firestore,
    );

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
          ChangeNotifierProvider<AuthService>.value(
            value: authService,
          ),
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChildTasksScreen(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Take Out Trash'), findsOneWidget);

    expect(
      find.text('Approved'),
      findsOneWidget,
    );

    expect(
      find.text('Awaiting Approval'),
      findsNothing,
    );
  },
);
  });
}