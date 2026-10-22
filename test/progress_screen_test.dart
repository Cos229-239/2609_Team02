import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:famotive/app/routes.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/rewards/screens/progress_screen.dart';

void main() {
  group('ProgressScreen navigation tests', () {
    testWidgets("tapping a child asks to open Rex in kid mode for that child", (tester) async {
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
      final pushed = <RouteSettings>[];

      await tester.pumpWidget(
        ChangeNotifierProvider<DatabaseService>.value(
          value: db,
          child: MaterialApp(
            home: const Scaffold(body: ProgressScreen()),
            // Rex's WebView can't run in widget tests: record the push instead.
            onGenerateRoute: (settings) {
              pushed.add(settings);
              return MaterialPageRoute(builder: (_) => const Scaffold(body: Text('rex')), settings: settings);
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Sally Simmons'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rex-kid-mode-dialog')), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);

      await tester.tap(find.text('Sally Simmons'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rex-kid-mode-start')));
      await tester.pumpAndSettle();
      expect(pushed.single.name, AppRoutes.rexRoom);
      expect(pushed.single.arguments, 'child-1');
    });

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
