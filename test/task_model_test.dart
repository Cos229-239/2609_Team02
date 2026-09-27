import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';

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
}
