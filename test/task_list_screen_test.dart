import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/models/reward.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/screens/task_list_screen.dart';

void main() {
  group('TaskListScreen layout regression tests', () {
    testWidgets(
      'reward cards do not overflow with multi-line titles at phone width',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));

        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
        });

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
        ];

        databaseService.availableRewards = [
          const Reward(
            id: 'reward-1',
            title: '+30 Minutes Game Time',
            type: RewardType.screenTime,
            xpCost: 200,
            icon: '🎮',
          ),
        ];

        await tester.pumpWidget(
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
            child: const MaterialApp(home: TaskListScreen(childId: 'child-1')),
          ),
        );

        await tester.pump();

        expect(find.text('+30 Minutes Game Time'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
  'groups child tasks by lifecycle status',
  (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

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
    ];

    databaseService.tasks = [
      TaskModel(
        id: 'task-pending',
        title: 'Clean Bedroom',
        description: '',
        rewardXp: 25,
        status: TaskStatus.pending,
        assignedToUserId: 'child-1',
      ),
      TaskModel(
        id: 'task-awaiting',
        title: 'Make the Bed',
        description: '',
        rewardXp: 50,
        status: TaskStatus.completed,
        assignedToUserId: 'child-1',
      ),
      TaskModel(
        id: 'task-approved',
        title: 'Laundry',
        description: '',
        rewardXp: 50,
        status: TaskStatus.approved,
        assignedToUserId: 'child-1',
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: databaseService,
        child: const MaterialApp(
          home: TaskListScreen(childId: 'child-1'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Assigned/Pending'), findsOneWidget);
    expect(find.text('Awaiting Approval'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);

    expect(find.text('Clean Bedroom'), findsOneWidget);
    expect(find.text('Make the Bed'), findsOneWidget);
    expect(find.text('Laundry'), findsOneWidget);
  },
);
  });
}
