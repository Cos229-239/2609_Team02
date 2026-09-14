import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/database_service.dart';
import 'package:famotive/features/tasks/services/task_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });

  group('TaskService', () {
    test('marks a task as completed', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';
      const taskId = 'task-2';

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .set(
            const TaskModel(
              id: taskId,
              title: 'Clean Room',
              assignedToUserId: 'child-1',
            ).toFirestore(),
          );

      db.bindHousehold(householdId);

      await service.markComplete(taskId);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      expect(taskSnapshot.data()?['status'], TaskStatus.completed.name);
    });

    test(
      'returns a completed task to pending when completion is undone',
      () async {
        final firestore = FakeFirebaseFirestore();
        final db = DatabaseService(firestore: firestore);
        final service = TaskService(db);

        const householdId = 'household-1';
        const taskId = 'task-1';

        await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .set(
              const TaskModel(
                id: taskId,
                title: 'Clean Room',
                assignedToUserId: 'child-1',
                status: TaskStatus.completed,
              ).toFirestore(),
            );

        db.bindHousehold(householdId);

        await service.uncomplete(taskId);

        final taskSnapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .get();

        expect(taskSnapshot.data()?['status'], TaskStatus.pending.name);
      },
    );

    test('approves a completed task and awards XP to the child', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';
      const taskId = 'task-2';
      const childId = 'child-1';
      const startingXp = 120;

      await firestore.collection('users').doc(childId).set({'xp': startingXp});

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .set(
            const TaskModel(
              id: taskId,
              title: 'Clean Room',
              assignedToUserId: childId,
              rewardXp: 50,
              status: TaskStatus.completed,
            ).toFirestore(),
          );

      db.bindHousehold(householdId);

      await service.approve(taskId);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      final childSnapshot = await firestore
          .collection('users')
          .doc(childId)
          .get();

      expect(taskSnapshot.data()?['status'], TaskStatus.approved.name);
      expect(childSnapshot.data()?['xp'], startingXp + 50);
    });

    test('does not award XP more than once for the same task', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';
      const taskId = 'task-2';
      const childId = 'child-1';
      const startingXp = 120;

      await firestore.collection('users').doc(childId).set({'xp': startingXp});

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .set(
            const TaskModel(
              id: taskId,
              title: 'Clean Room',
              assignedToUserId: childId,
              rewardXp: 50,
              status: TaskStatus.completed,
            ).toFirestore(),
          );

      db.bindHousehold(householdId);

      await service.approve(taskId);
      await service.approve(taskId);

      final childSnapshot = await firestore
          .collection('users')
          .doc(childId)
          .get();

      expect(childSnapshot.data()?['xp'], startingXp + 50);
    });

    test('assigns a task to the expected child', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';

      db.bindHousehold(householdId);

      await service.assignTask(
        title: 'Take Out Trash',
        childId: 'child-1',
        rewardXp: 75,
        icon: '🗑️',
      );

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      expect(taskSnapshot.docs.length, 1);

      final taskData = taskSnapshot.docs.first.data();

      expect(taskData['title'], 'Take Out Trash');
      expect(taskData['assignedToUserId'], 'child-1');
      expect(taskData['rewardXp'], 75);
      expect(taskData['icon'], '🗑️');
      expect(taskData['status'], TaskStatus.pending.name);
    });

    test('returns only tasks assigned to the requested child', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';
      const childId = 'child-1';

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc('task-child-1')
          .set(
            const TaskModel(
              id: 'task-child-1',
              title: 'Clean Room',
              assignedToUserId: childId,
            ).toFirestore(),
          );

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc('task-parent-1')
          .set(
            const TaskModel(
              id: 'task-parent-1',
              title: 'Parent Only Task',
              assignedToUserId: 'parent-1',
            ).toFirestore(),
          );

      db.bindHousehold(householdId);

      await Future<void>.delayed(Duration.zero);

      final childTasks = service.tasksForChild(childId);

      expect(childTasks.length, 1);
      expect(childTasks.first.title, 'Clean Room');
      expect(childTasks.first.assignedToUserId, childId);
    });

    test('returns the correct task by id', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';
      const taskId = 'task-2';

      await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .set(
            const TaskModel(
              id: taskId,
              title: 'Clean Room',
              assignedToUserId: 'child-1',
            ).toFirestore(),
          );

      db.bindHousehold(householdId);

      await Future<void>.delayed(Duration.zero);

      final task = service.taskById(taskId);

      expect(task, isNotNull);
      expect(task!.id, taskId);
      expect(task.title, 'Clean Room');
    });

    test('returns null when task id does not exist', () async {
      final firestore = FakeFirebaseFirestore();
      final db = DatabaseService(firestore: firestore);
      final service = TaskService(db);

      const householdId = 'household-1';

      db.bindHousehold(householdId);

      await Future<void>.delayed(Duration.zero);

      final task = service.taskById('missing-task');

      expect(task, isNull);
    });
  });
}
