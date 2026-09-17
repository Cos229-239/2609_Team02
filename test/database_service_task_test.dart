import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  group('DatabaseService task lifecycle', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService databaseService;

    const householdId = 'household-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      databaseService = DatabaseService(firestore: firestore);
      databaseService.bindHousehold(householdId);
    });

    test('adds a task to the household task collection', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Take Out the Trash',
        assignedToUserId: 'child-1',
        rewardXp: 25,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      expect(snapshot.docs, hasLength(1));

      final savedTask = snapshot.docs.first.data();

      expect(savedTask['title'], 'Take Out the Trash');
      expect(savedTask['assignedToUserId'], 'child-1');
      expect(savedTask['rewardXp'], 25);
      expect(savedTask['status'], TaskStatus.pending.name);
    });

    test('allows a child to claim an available task', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Wash the Dishes',
        rewardXp: 30,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = snapshot.docs.first.id;

      await databaseService.claimTask(taskId, 'child-1');

      final updatedTask = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      expect(updatedTask.data()?['assignedToUserId'], 'child-1');
      expect(updatedTask.data()?['status'], TaskStatus.pending.name);
    });

    test('marks an assigned task as completed', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Clean Your Room',
        assignedToUserId: 'child-1',
        rewardXp: 40,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = snapshot.docs.first.id;

      await databaseService.completeTask(taskId);

      final updatedTask = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      expect(updatedTask.data()?['status'], TaskStatus.completed.name);
      expect(updatedTask.data()?['assignedToUserId'], 'child-1');
    });

    test(
      'approves a completed task and awards XP to the assigned child',
      () async {
        await firestore.collection('users').doc('child-1').set({
          'xp': 100,
          'householdId': householdId,
        });

        const task = TaskModel(
          id: 'task-1',
          title: 'Feed the Dog',
          assignedToUserId: 'child-1',
          rewardXp: 50,
          status: TaskStatus.completed,
        );

        await databaseService.addTask(task);

        final snapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = snapshot.docs.first.id;

        await databaseService.approveTask(taskId);

        final approvedTask = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .get();

        final child = await firestore.collection('users').doc('child-1').get();

        expect(approvedTask.data()?['status'], TaskStatus.approved.name);
        expect(child.data()?['xp'], 150);
      },
    );

    test(
      'does not approve a task before the child marks it complete',
      () async {
        await firestore.collection('users').doc('child-1').set({
          'xp': 100,
          'householdId': householdId,
        });

        const task = TaskModel(
          id: 'task-1',
          title: 'Do Homework',
          assignedToUserId: 'child-1',
          rewardXp: 50,
          status: TaskStatus.pending,
        );

        await databaseService.addTask(task);

        final snapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = snapshot.docs.first.id;

        await databaseService.approveTask(taskId);

        final taskAfterApprovalAttempt = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .get();

        final child = await firestore.collection('users').doc('child-1').get();

        expect(
          taskAfterApprovalAttempt.data()?['status'],
          TaskStatus.pending.name,
        );

        expect(child.data()?['xp'], 100);
      },
    );

    test('does not award XP more than once for the same task', () async {
      await firestore.collection('users').doc('child-1').set({
        'xp': 100,
        'householdId': householdId,
      });

      const task = TaskModel(
        id: 'task-1',
        title: 'Clean the Kitchen',
        assignedToUserId: 'child-1',
        rewardXp: 50,
        status: TaskStatus.completed,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = snapshot.docs.first.id;

      // First approval should award the XP.
      await databaseService.approveTask(taskId);

      // A second approval attempt should not award it again.
      await databaseService.approveTask(taskId);

      final approvedTask = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      final child = await firestore.collection('users').doc('child-1').get();

      expect(approvedTask.data()?['status'], TaskStatus.approved.name);
      expect(child.data()?['xp'], 150);
    });

    test(
      'returns a completed task to pending when completion is undone',
      () async {
        const task = TaskModel(
          id: 'task-1',
          title: 'Put Away Laundry',
          assignedToUserId: 'child-1',
          rewardXp: 30,
          status: TaskStatus.completed,
        );

        await databaseService.addTask(task);

        final snapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = snapshot.docs.first.id;

        await databaseService.uncompleteTask(taskId);

        final updatedTask = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .get();

        expect(updatedTask.data()?['status'], TaskStatus.pending.name);
        expect(updatedTask.data()?['assignedToUserId'], 'child-1');
      },
    );

    test('does not return an approved task to pending', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Take Out the Trash',
        assignedToUserId: 'child-1',
        rewardXp: 50,
        status: TaskStatus.approved,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = snapshot.docs.first.id;

      await databaseService.uncompleteTask(taskId);

      final updatedTask = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      expect(updatedTask.data()?['status'], TaskStatus.approved.name);
    });

    test('tasksForUser returns only tasks assigned to that child', () async {
      const childOneTask = TaskModel(
        id: 'task-1',
        title: 'Clean Bedroom',
        assignedToUserId: 'child-1',
      );

      const childTwoTask = TaskModel(
        id: 'task-2',
        title: 'Feed the Dog',
        assignedToUserId: 'child-2',
      );

      await databaseService.addTask(childOneTask);
      await databaseService.addTask(childTwoTask);

      // Allow the Firestore listener in DatabaseService to receive the updates.
      await Future<void>.delayed(Duration.zero);

      final childOneTasks = databaseService.tasksForUser('child-1');

      expect(childOneTasks, hasLength(1));
      expect(childOneTasks.first.title, 'Clean Bedroom');
      expect(childOneTasks.first.assignedToUserId, 'child-1');
    });

    test('availableTasks returns only unassigned tasks', () async {
      const availableTask = TaskModel(
        id: 'task-1',
        title: 'Vacuum Living Room',
      );

      const assignedTask = TaskModel(
        id: 'task-2',
        title: 'Wash Dishes',
        assignedToUserId: 'child-1',
      );

      await databaseService.addTask(availableTask);
      await databaseService.addTask(assignedTask);

      // Allow the Firestore listener in DatabaseService to receive the updates.
      await Future<void>.delayed(Duration.zero);

      final availableTasks = databaseService.availableTasks;

      expect(availableTasks, hasLength(1));
      expect(availableTasks.first.title, 'Vacuum Living Room');
      expect(availableTasks.first.assignedToUserId, isNull);
    });

    test(
      'does not allow a second child to claim an already assigned task',
      () async {
        const task = TaskModel(
          id: 'task-1',
          title: 'Walk the Dog',
          rewardXp: 40,
        );

        await databaseService.addTask(task);

        final snapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = snapshot.docs.first.id;

        // First child claims the available task.
        await databaseService.claimTask(taskId, 'child-1');

        // Second child attempts to claim the same task.
        await databaseService.claimTask(taskId, 'child-2');

        final claimedTask = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .doc(taskId)
            .get();

        expect(claimedTask.data()?['assignedToUserId'], 'child-1');
      },
    );
  });
}
