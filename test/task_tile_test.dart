import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/features/tasks/widgets/task_tile.dart';

void main() {
  group('TaskTile layout regression tests', () {
    testWidgets('completed task status does not overflow at phone width', (
      tester,
    ) async {
      // Match a typical phone-sized viewport.
      await tester.binding.setSurfaceSize(const Size(390, 844));

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      const task = TaskModel(
        id: 'task-awaiting',
        title: 'Piano Lessons',
        rewardXp: 50,
        status: TaskStatus.completed,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: TaskTile(task: task),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Piano Lessons'), findsOneWidget);
      expect(find.text('Pending Approval'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
