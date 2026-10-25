import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:famotive/shared/widgets/number_stepper.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/user.dart';
import 'package:famotive/core/services/auth_service.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/screens/create_task_screen.dart';
import 'package:famotive/shared/widgets/app_button.dart';

void main() {
  testWidgets('challenge mode returns a task without saving it', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('households').doc('household-1').set({
      'name': 'Test Household',
      'ownerId': 'parent-1',
      'memberIds': ['parent-1', 'child-1'],
      'timezone': 'America/New_York',
    });

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
    db.bindHousehold('household-1');

    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20 && db.children.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });

    expect(db.children, hasLength(1));
    expect(db.children.single.id, 'child-1');

    TaskModel? returnedTask;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returnedTask = await Navigator.of(context).push<TaskModel>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const CreateTaskScreen(challengeDraftMode: true),
                      ),
                    );
                  },
                  child: const Text('Open Task Form'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the shared task creation screen.
    await tester.tap(find.text('Open Task Form'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateTaskScreen), findsOneWidget);
    expect(find.text('Create Task'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Name this Task:'),
      150,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.pumpAndSettle();

    // Enter a task title using the field's hint text.
    final titleField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. Take Out the Trash',
    );

    expect(titleField, findsOneWidget);

    await tester.enterText(titleField, 'Clean Bathroom Sink');
    await tester.pump();
    // Locate the XP and coin reward controls.
    final xpStepper = find.byWidgetPredicate(
      (widget) => widget is NumberStepper && widget.label == 'XP Earned',
    );

    final coinsStepper = find.byWidgetPredicate(
      (widget) => widget is NumberStepper && widget.label == 'Coins Earned',
    );

    // Scroll to the XP reward control first.
    await tester.scrollUntilVisible(
      xpStepper,
      100,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.pumpAndSettle();

    expect(xpStepper, findsOneWidget);

    // Read the initial reward values.
    final initialXp = tester.widget<NumberStepper>(xpStepper).value;
    final initialCoins = tester.widget<NumberStepper>(coinsStepper).value;

    // Increase XP by 5.
    await tester.tap(
      find.descendant(
        of: xpStepper,
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    // Increase coins by 5.
    await tester.tap(
      find.descendant(
        of: coinsStepper,
        matching: find.byIcon(Icons.add_circle_outline),
      ),
    );
    await tester.pump();

    // Find the child assignment option.
    final childOption = find.text('Test Child');

    await tester.scrollUntilVisible(
      find.text('Assign To:'),
      150,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(childOption, findsOneWidget);

    // Assign the chore to Test Child.
    await tester.tap(childOption);
    await tester.pump();

    // Find the actual submission button.
    final createButton = find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == 'Create Task',
    );

    await tester.scrollUntilVisible(
      createButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.pumpAndSettle();

    expect(createButton, findsOneWidget);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    // Verify the configured task was returned.
    expect(returnedTask, isNotNull);
    expect(returnedTask!.title, 'Clean Bathroom Sink');
    expect(returnedTask!.rewardXp, initialXp + 5);
    expect(returnedTask!.coinReward, initialCoins + 5);
    expect(returnedTask!.assignedToUserId, 'child-1');
    expect(returnedTask!.goalId, isNull);
    expect(returnedTask!.status, TaskStatus.pending);

    // Verify the task creation screen closed.
    expect(find.byType(CreateTaskScreen), findsNothing);
    expect(find.text('Open Task Form'), findsOneWidget);

    // Challenge mode must not save the task before confirmation.
    final savedTasks = await firestore
        .collection('households')
        .doc('household-1')
        .collection('tasks')
        .get();

    expect(savedTasks.docs, isEmpty);

    // Clean up.
    await tester.pumpWidget(const SizedBox.shrink());

    db.dispose();
    authService.dispose();
  });

  testWidgets('cancelling challenge task creation returns no task', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('households').doc('household-1').set({
      'name': 'Test Household',
      'ownerId': 'parent-1',
      'memberIds': ['parent-1', 'child-1'],
      'timezone': 'America/New_York',
    });

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
    db.bindHousehold('household-1');
    // Allow the asynchronous household and member listeners to initialize.
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 20 && db.children.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });

    expect(db.children, hasLength(1));
    expect(db.children.single.id, 'child-1');

    db.familyMembers = [
      const AppUser(
        id: 'parent-1',
        name: 'Test Parent',
        email: 'parent@test.com',
        role: UserRole.parent,
        householdId: 'household-1',
      ),
      const AppUser(
        id: 'child-1',
        name: 'Test Child',
        email: 'child@test.com',
        role: UserRole.child,
        householdId: 'household-1',
      ),
    ];
    expect(db.children.length, 1);
    expect(db.children.first.id, 'child-1');
    expect(db.children.first.name, 'Test Child');

    TaskModel? returnedTask;
    bool navigationCompleted = false;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<DatabaseService>.value(value: db),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returnedTask = await Navigator.of(context).push<TaskModel>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const CreateTaskScreen(challengeDraftMode: true),
                      ),
                    );
                    navigationCompleted = true;
                  },
                  child: const Text('Open Task Form'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Task Form'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateTaskScreen), findsOneWidget);

    // Cancel using the actual Create Task screen's back button.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(navigationCompleted, isTrue);
    expect(returnedTask, isNull);
    expect(find.byType(CreateTaskScreen), findsNothing);

    // Cancelling must not create a task in Firestore.
    final savedTasks = await firestore
        .collection('households')
        .doc('household-1')
        .collection('tasks')
        .get();

    expect(savedTasks.docs, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    db.dispose();
    authService.dispose();
  });
}
