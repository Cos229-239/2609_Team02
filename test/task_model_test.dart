import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/task_schedule.dart';

void main() {
  group('TaskModel archiving', () {
    test('is not archived when createdAt is null', () {
      const task = TaskModel(id: 't1', title: 'Test');
      expect(task.isArchived, isFalse);
    });

    test('is not archived when createdAt is recent', () {
      final task = TaskModel(
        id: 't1',
        title: 'Test',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(task.isArchived, isFalse);
    });

    test('auto-archives once older than the configured threshold', () {
      final task = TaskModel(
        id: 't1',
        title: 'Test',
        createdAt: DateTime.now().subtract(const Duration(days: 61)),
      );
      expect(task.isAgedOut, isTrue);
      expect(task.isArchived, isTrue);
    });

    test('manual archive flag archives regardless of age', () {
      const task = TaskModel(id: 't1', title: 'Test', archived: true);
      expect(task.isAgedOut, isFalse);
      expect(task.isArchived, isTrue);
    });
  });

  group('TaskModel.copyWith', () {
    test('can explicitly clear assignedToUserId and dueDate', () {
      final original = TaskModel(
        id: 't1',
        title: 'Test',
        assignedToUserId: 'child-1',
        dueDate: DateTime(2026, 1, 1),
      );

      final updated = original.copyWith(
        clearAssignedToUserId: true,
        clearDueDate: true,
      );

      expect(updated.assignedToUserId, isNull);
      expect(updated.dueDate, isNull);
      // Everything else is preserved.
      expect(updated.title, 'Test');
    });

    test('updates fields without touching the rest', () {
      const original = TaskModel(
        id: 't1',
        title: 'Test',
        rewardXp: 20,
        coinReward: 5,
      );

      final updated = original.copyWith(rewardXp: 40, coinReward: 15);

      expect(updated.id, 't1');
      expect(updated.title, 'Test');
      expect(updated.rewardXp, 40);
      expect(updated.coinReward, 15);
    });
  });

  group('TaskModel.defaultAvailableCatalog', () {
    test('seeds due dates at local midnight, not the creation time', () {
      final tasks = TaskModel.defaultAvailableCatalog(DateTime(2026, 10, 1, 16, 42, 7));
      expect(tasks.map((t) => t.dueDate), [DateTime(2026, 10, 4)]);
    });

    test('rolls over month ends', () {
      final tasks = TaskModel.defaultAvailableCatalog(DateTime(2026, 12, 30, 9));
      expect(tasks.single.dueDate, DateTime(2027, 1, 2));
    });
  });

  group('TaskModel repeat fields', () {
    test('one-time tasks', () {
      const task = TaskModel(id: 't1', title: 'Test');
      expect(task.isRecurring, isFalse);
      expect(task.repeatLabel, 'One-time Task');
      expect(task.toFirestore()['scheduleId'], isNull);
    });

    test('occurrences keep their schedule through copyWith', () {
      const task = TaskModel(id: 's1_20261005', title: 'Dog', repeat: TaskRepeat.daily, scheduleId: 's1');
      final copy = task.copyWith(title: 'Feed the Dog');
      expect(copy.isRecurring, isTrue);
      expect(copy.scheduleId, 's1');
      expect(copy.repeatLabel, 'Daily Task');
      expect(copy.toFirestore()['repeat'], 'daily');
    });

    test("tomorrow's occurrence is upcoming; today's and one-time tasks are not", () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      TaskModel occ(DateTime due) => TaskModel(id: 'x', title: 'Dog', scheduleId: 's1', dueDate: due);
      expect(occ(tomorrow).isUpcoming, isTrue);
      expect(occ(today).isUpcoming, isFalse);
      expect(TaskModel(id: 'y', title: 'One-off', dueDate: tomorrow).isUpcoming, isFalse);
    });
  });
}
