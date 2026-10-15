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
import 'package:famotive/features/tasks/widgets/task_view_card.dart';

Future<AuthService> _signedIn(FakeFirebaseFirestore firestore, AppUser user) async {
  await firestore.collection('users').doc(user.id).set(user.toFirestore());
  final auth = AuthService(
    auth: MockFirebaseAuth(
      mockUser: MockUser(uid: user.id, email: user.email, displayName: user.name),
      signedIn: true,
    ),
    firestore: firestore,
  );
  await auth.tryRestoreSession();
  return auth;
}

Widget _app(AuthService auth, DatabaseService db, Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<DatabaseService>.value(value: db),
      ],
      child: MaterialApp(home: Scaffold(body: home)),
    );

void main() {
  const child = AppUser(
    id: 'child-1',
    name: 'Test Child',
    email: 'child@test.com',
    role: UserRole.child,
    householdId: 'household-1',
  );
  const parent = AppUser(
    id: 'parent-1',
    name: 'Test Parent',
    email: 'parent@test.com',
    role: UserRole.parent,
    householdId: 'household-1',
  );

  testWidgets('child taps a task tile and gets the complete action', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = await _signedIn(firestore, child);
    final db = DatabaseService(firestore: firestore)
      ..tasks = [
        const TaskModel(
          id: 'mine',
          title: 'Clean Bedroom',
          description: 'Bed made, floor clear.',
          assignedToUserId: 'child-1',
          rewardXp: 25,
        ),
      ];

    await tester.pumpWidget(_app(auth, db, const ChildTasksScreen()));
    await tester.pump();

    await tester.tap(find.text('Clean Bedroom'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskViewCard), findsOneWidget);
    expect(find.text('Bed made, floor clear.'), findsOneWidget);
    expect(find.text('Mark as Complete'), findsOneWidget);
    expect(find.text('Edit Task'), findsNothing);
  });

  testWidgets('child sees Claim for an unclaimed household task', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = await _signedIn(firestore, child);
    final db = DatabaseService(firestore: firestore)
      ..tasks = [const TaskModel(id: 'pool', title: 'Sweep Porch', rewardXp: 10)];

    await tester.pumpWidget(_app(
      auth,
      db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTaskViewSheet(context, 'pool'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Claim Task'), findsOneWidget);
    expect(find.text('Mark as Complete'), findsNothing);
  });

  testWidgets('parent gets mark complete and edit for a pending task', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = await _signedIn(firestore, parent);
    final db = DatabaseService(firestore: firestore)
      ..familyMembers = [child, parent]
      ..tasks = [
        const TaskModel(
          id: 'assigned',
          title: 'Feed the Dog',
          assignedToUserId: 'child-1',
          rewardXp: 25,
        ),
      ];

    await tester.pumpWidget(_app(
      auth,
      db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTaskViewSheet(context, 'assigned'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as Complete'), findsOneWidget);
    expect(find.text('Edit Task'), findsOneWidget);
    expect(find.textContaining('Test Child'), findsOneWidget);
  });
}
