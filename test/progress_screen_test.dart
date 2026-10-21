import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:famotive/features/tasks/screens/task_list_screen.dart';

import 'package:famotive/app/routes.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/rewards/screens/progress_screen.dart';

void main() {
  group('ProgressScreen navigation tests', () {
    testWidgets(
      'tapping a child progress card opens that child task list',
      (tester) async {
        final databaseService = DatabaseService(
          firestore: FakeFirebaseFirestore(),
        );

        databaseService.familyMembers = [
          const AppUser(
            id: 'child-1',
            name: 'Sally Simmons',
            email: 'sally@test.com',
            role: UserRole.child,
            xp: 100,
            householdId: 'household-1',
          ),
          const AppUser(
            id: 'child-2',
            name: 'Billy Simmons',
            email: 'billy@test.com',
            role: UserRole.child,
            xp: 50,
            householdId: 'household-1',
          ),
        ];

        databaseService.tasks = [
          TaskModel(
            id: 'sally-task',
            title: 'Sally Task',
            description: '',
            rewardXp: 25,
            status: TaskStatus.pending,
            assignedToUserId: 'child-1',
          ),
          TaskModel(
            id: 'billy-task',
            title: 'Billy Task',
            description: '',
            rewardXp: 25,
            status: TaskStatus.pending,
            assignedToUserId: 'child-2',
          ),
        ];

        await tester.pumpWidget(
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
            child: MaterialApp(
              home: const ProgressScreen(),
              onGenerateRoute: AppRoutes.onGenerateRoute,
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Sally Simmons'), findsOneWidget);
        expect(find.text('Billy Simmons'), findsOneWidget);

        await tester.tap(find.text('Sally Simmons'));
        await tester.pumpAndSettle();

        expect(find.byType(TaskListScreen), findsOneWidget);

        final taskListScreen = tester.widget<TaskListScreen>(
          find.byType(TaskListScreen),
        );

        expect(taskListScreen.childId, 'child-1');
      },
    );

    testWidgets('task categories are drawers that open and close', (
      tester,
    ) async {
      final db = DatabaseService(firestore: FakeFirebaseFirestore());
      db.familyMembers = [
        const AppUser(
          id: 'child-1',
          name: 'Sally Simmons',
          email: 'sally@test.com',
          role: UserRole.child,
          householdId: 'household-1',
        ),
      ];
      db.tasks = [
        TaskModel(
          id: 'pending-task',
          title: 'Feed the Dog',
          description: '',
          rewardXp: 25,
          status: TaskStatus.pending,
          assignedToUserId: 'child-1',
        ),
        TaskModel(
          id: 'awaiting-task',
          title: 'Make the Bed',
          description: '',
          rewardXp: 25,
          status: TaskStatus.completed,
          assignedToUserId: 'child-1',
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<DatabaseService>.value(
          value: db,
          child: const MaterialApp(home: Scaffold(body: ProgressScreen())),
        ),
      );
      await tester.pump();

      // Awaiting Approval needs action, so it starts open; Pending starts closed.
      expect(find.text('Make the Bed'), findsOneWidget);
      expect(find.text('Feed the Dog'), findsNothing);

      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();
      expect(find.text('Feed the Dog'), findsOneWidget);

      await tester.tap(find.text('Pending'));
      await tester.pumpAndSettle();
      expect(find.text('Feed the Dog'), findsNothing);
    });
  });
}
