import 'package:famotive/core/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/services/task_service.dart';

void main() {
  group('TaskModel', () {
    test('creates a task with the expected properties', () {
      const task = TaskModel(
        id: 'task-1',
        title: 'Clean Room',
        description: 'Clean and organize the bedroom.',
        assignedToUserId: 'child-1',
        rewardXp: 75,
      );

      expect(task.id, 'task-1');
      expect(task.title, 'Clean Room');
      expect(task.description, 'Clean and organize the bedroom.');
      expect(task.assignedToUserId, 'child-1');
      expect(task.rewardXp, 75);
    });
  });
  test('uses the expected default values', () {
    const task = TaskModel(
      id: 'task-2',
      title: 'Take Out Trash',
      assignedToUserId: 'child-1',
    );

    expect(task.description, '');
    expect(task.icon, '🧹');
    expect(task.rewardXp, 50);
    expect(task.status, TaskStatus.pending);
    expect(task.isRecurring, false);
    expect(task.dueDate, isNull);
  });

  test('copyWith updates task properties', () {
    const originalTask = TaskModel(
      id: 'task-3',
      title: 'Wash Dishes',
      description: 'Clean the dishes after dinner.',
      assignedToUserId: 'child-1',
      rewardXp: 50,
    );

    final updatedTask = originalTask.copyWith(
      title: 'Wash Dinner Dishes',
      description: 'Clean and put away the dishes.',
      rewardXp: 100,
      status: TaskStatus.completed,
      isRecurring: true,
    );

    expect(updatedTask.id, 'task-3');
    expect(updatedTask.title, 'Wash Dinner Dishes');
    expect(updatedTask.description, 'Clean and put away the dishes.');
    expect(updatedTask.assignedToUserId, 'child-1');
    expect(updatedTask.rewardXp, 100);
    expect(updatedTask.status, TaskStatus.completed);
    expect(updatedTask.isRecurring, true);
  });

  test('identifies a pending task correctly', () {
    const task = TaskModel(
      id: 'task-4',
      title: 'Feed the Dog',
      assignedToUserId: 'child-1',
    );

    expect(task.isPending, true);
    expect(task.isCompleted, false);
  });

  test('identifies a completed task correctly', () {
    const task = TaskModel(
      id: 'task-5',
      title: 'Feed the Dog',
      assignedToUserId: 'child-1',
      status: TaskStatus.completed,
    );

    expect(task.isPending, false);
    expect(task.isCompleted, true);
  });

  test('treats an approved task as completed', () {
    const task = TaskModel(
      id: 'task-6',
      title: 'Feed the Dog',
      assignedToUserId: 'child-1',
      status: TaskStatus.approved,
    );

    expect(task.isPending, false);
    expect(task.isCompleted, true);
  });

  group('TaskService', () {
    test('marks a task as completed', () {
      final db = DatabaseService();
      final service = TaskService(db);

      final task = service.markComplete('task-2');

      expect(task.status, TaskStatus.completed);
      expect(task.isCompleted, true);
    });
  });
  test('approves a completed task and awards XP to the child', () {
    final db = DatabaseService();
    final service = TaskService(db);

    final childBefore = db.userById('user-child-alex');
    final startingXp = childBefore!.xp;

    service.markComplete('task-2');
    service.approve('task-2');

    final approvedTask = service.taskById('task-2');
    final childAfter = db.userById('user-child-alex');

    expect(approvedTask!.status, TaskStatus.approved);
    expect(childAfter!.xp, startingXp + 50);
  });

  test('does not award XP more than once for the same task', () {
    final db = DatabaseService();
    final service = TaskService(db);

    final childBefore = db.userById('user-child-alex');
    final startingXp = childBefore!.xp;

    service.markComplete('task-2');
    service.approve('task-2');
    service.approve('task-2');

    final childAfter = db.userById('user-child-alex');

    expect(childAfter!.xp, startingXp + 50);
  });

  test('assigns a task to the expected child', () {
    final db = DatabaseService();
    final service = TaskService(db);

    service.assignTask(
      title: 'Take Out Trash',
      childId: 'user-child-alex',
      rewardXp: 75,
      icon: '🗑️',
    );

    final assignedTask = db.tasks.last;

    expect(assignedTask.title, 'Take Out Trash');
    expect(assignedTask.assignedToUserId, 'user-child-alex');
    expect(assignedTask.rewardXp, 75);
    expect(assignedTask.icon, '🗑️');
    expect(assignedTask.status, TaskStatus.pending);
  });

  test('returns only tasks assigned to the requested child', () {
    final db = DatabaseService();
    final service = TaskService(db);

    service.assignTask(title: 'Parent Only Task', childId: 'user-parent-1');

    final childTasks = service.tasksForChild('user-child-alex');

    expect(
      childTasks.every((task) => task.assignedToUserId == 'user-child-alex'),
      true,
    );
  });

  test('returns the correct task by id', () {
    final db = DatabaseService();
    final service = TaskService(db);

    final task = service.taskById('task-2');

    expect(task, isNotNull);
    expect(task!.id, 'task-2');
    expect(task.title, 'Clean Room');
  });

  test('throws when completing a task with an invalid id', () {
    final db = DatabaseService();
    final service = TaskService(db);

    expect(
      () => service.markComplete('missing-task'),
      throwsA(isA<RangeError>()),
    );
  });

  test('returns null when task id does not exist', () {
    final db = DatabaseService();
    final service = TaskService(db);

    final task = service.taskById('missing-task');

    expect(task, isNull);
  });
}
