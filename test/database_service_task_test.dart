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

    test('approves a completed task and awards coins to the assigned child', () async {
      await firestore.collection('users').doc('child-1').set({
        'xp': 0,
        'coins': 20,
        'householdId': householdId,
      });

      const task = TaskModel(
        id: 'task-1',
        title: 'Feed the Dog',
        assignedToUserId: 'child-1',
        rewardXp: 50,
        coinReward: 15,
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

      final child = await firestore.collection('users').doc('child-1').get();

      expect(child.data()?['xp'], 50);
      expect(child.data()?['coins'], 35);
    });

    test('updateTask overwrites the editable fields of an existing task', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Old Title',
        rewardXp: 10,
        coinReward: 5,
      );

      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = snapshot.docs.first.id;
      final saved = TaskModel.fromFirestore(snapshot.docs.first);

      final updated = saved.copyWith(
        title: 'New Title',
        description: 'Updated description',
        rewardXp: 40,
        coinReward: 20,
      );

      await databaseService.updateTask(taskId, updated);

      final refreshed = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();

      expect(refreshed.data()?['title'], 'New Title');
      expect(refreshed.data()?['description'], 'Updated description');
      expect(refreshed.data()?['rewardXp'], 40);
      expect(refreshed.data()?['coinReward'], 20);
    });

    test('setTaskArchived toggles the archived flag', () async {
      const task = TaskModel(id: 'task-1', title: 'Archive Me');
      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();
      final taskId = snapshot.docs.first.id;

      await databaseService.setTaskArchived(taskId, true);
      var doc = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(doc.data()?['archived'], isTrue);

      await databaseService.setTaskArchived(taskId, false);
      doc = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(doc.data()?['archived'], isFalse);
    });

    test('removeTask permanently deletes the task', () async {
      const task = TaskModel(id: 'task-1', title: 'Delete Me');
      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();
      final taskId = snapshot.docs.first.id;

      await databaseService.removeTask(taskId);

      final afterDelete = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();
      expect(afterDelete.docs, isEmpty);
    });

    test('archived tasks are excluded from activeTasks/tasksForUser/availableTasks', () async {
      const archivedAssigned = TaskModel(
        id: 'task-1',
        title: 'Archived Assigned',
        assignedToUserId: 'child-1',
        archived: true,
      );
      const activeAssigned = TaskModel(
        id: 'task-2',
        title: 'Active Assigned',
        assignedToUserId: 'child-1',
      );
      const archivedAvailable = TaskModel(
        id: 'task-3',
        title: 'Archived Available',
        archived: true,
      );
      const activeAvailable = TaskModel(
        id: 'task-4',
        title: 'Active Available',
      );

      await databaseService.addTask(archivedAssigned);
      await databaseService.addTask(activeAssigned);
      await databaseService.addTask(archivedAvailable);
      await databaseService.addTask(activeAvailable);

      // Allow the Firestore listener in DatabaseService to receive the updates.
      await Future<void>.delayed(Duration.zero);

      expect(databaseService.archivedTasks.map((t) => t.title), containsAll(['Archived Assigned', 'Archived Available']));

      final myTasks = databaseService.tasksForUser('child-1');
      expect(myTasks, hasLength(1));
      expect(myTasks.first.title, 'Active Assigned');

      final available = databaseService.availableTasks;
      expect(available, hasLength(1));
      expect(available.first.title, 'Active Available');
    });

    test('addTask returns the id Firestore assigned the new document', () async {
      const task = TaskModel(id: 'placeholder', title: 'Water Plants');

      final newId = await databaseService.addTask(task);

      final doc = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(newId)
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()?['title'], 'Water Plants');
    });

    test('reassignTask changes who a task is assigned to', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Mow the Lawn',
        assignedToUserId: 'child-1',
        status: TaskStatus.completed,
      );
      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();
      final taskId = snapshot.docs.first.id;

      await databaseService.reassignTask(taskId, 'child-2');

      final reassigned = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(reassigned.data()?['assignedToUserId'], 'child-2');
    });

    test('reassignTask can move a task back to the household pool', () async {
      const task = TaskModel(
        id: 'task-1',
        title: 'Mow the Lawn',
        assignedToUserId: 'child-1',
      );
      await databaseService.addTask(task);

      final snapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();
      final taskId = snapshot.docs.first.id;

      await databaseService.reassignTask(taskId, null);

      final reassigned = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .doc(taskId)
          .get();
      expect(reassigned.data()?['assignedToUserId'], isNull);
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
