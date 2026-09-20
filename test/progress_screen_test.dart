import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/rewards/screens/progress_screen.dart';

void main() {
  group('ProgressScreen task status regression tests', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService databaseService;

    const householdId = 'household-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      databaseService = DatabaseService(firestore: firestore);
      databaseService.bindHousehold(householdId);
    });

    testWidgets(
      'completed child task displays as awaiting approval',
      (tester) async {
        databaseService.tasks = [
          const TaskModel(
            id: 'task-awaiting',
            title: 'Regression Test Chore',
            assignedToUserId: 'child-1',
            rewardXp: 25,
            status: TaskStatus.completed,
          ),
        ];

        await tester.pumpWidget(
          ChangeNotifierProvider<DatabaseService>.value(
            value: databaseService,
            child: const MaterialApp(
              home: Scaffold(
                body: ProgressScreen(),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Regression Test Chore'), findsOneWidget);

        expect(
          find.text('Awaiting Approval'),
          findsNWidgets(2),
        );

        expect(find.text('Approved'), findsNothing);
      },
    );

    testWidgets(
  'approved task displays as completed',
  (tester) async {
    databaseService.tasks = [
      const TaskModel(
        id: 'task-approved',
        title: 'Approved Regression Test Chore',
        assignedToUserId: 'child-1',
        rewardXp: 25,
        status: TaskStatus.approved,
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<DatabaseService>.value(
        value: databaseService,
        child: const MaterialApp(
          home: Scaffold(
            body: ProgressScreen(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text('Approved Regression Test Chore'),
      findsOneWidget,
    );

    expect(find.text('Approved'), findsOneWidget);
  },
);
  });
}