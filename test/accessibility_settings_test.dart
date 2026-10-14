import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/accessibility_settings.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/widgets/task_swipe.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const task = TaskModel(id: 't1', title: 'Feed the Dog', rewardXp: 10, assignedToUserId: 'c1');

  Widget app(AccessibilitySettings? settings) {
    final row = ParentTaskSwipe(task: task, child: const ListTile(title: Text('Feed the Dog')));
    final db = ChangeNotifierProvider<DatabaseService>.value(
      value: DatabaseService(firestore: FakeFirebaseFirestore()),
      child: MaterialApp(home: Scaffold(body: row)),
    );
    if (settings == null) return db;
    return ChangeNotifierProvider<AccessibilitySettings>.value(value: settings, child: db);
  }

  testWidgets('task rows are swipeable by default', (tester) async {
    await tester.pumpWidget(app(null));
    expect(find.byType(Dismissible), findsOneWidget);
  });

  testWidgets('turning off Swipe Actions makes task rows tap-only', (tester) async {
    final settings = AccessibilitySettings();
    await tester.pumpWidget(app(settings));
    expect(find.byType(Dismissible), findsOneWidget);

    await settings.setSwipeActions(false);
    await tester.pump();
    expect(find.byType(Dismissible), findsNothing);
    expect(find.text('Feed the Dog'), findsOneWidget);
  });
}
