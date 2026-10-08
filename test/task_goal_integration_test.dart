import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:famotive/core/models/goal.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/services/database_service.dart';

void main() {
  group('Task approval goal integration', () {
    late FakeFirebaseFirestore firestore;
    late DatabaseService databaseService;

    const householdId = 'household-1';
    const childId = 'child-1';

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      databaseService = DatabaseService(firestore: firestore);
      databaseService.bindHousehold(householdId);

      await firestore.collection('households').doc(householdId).set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', childId],
      });

      await firestore.collection('users').doc(childId).set({
        'xp': 0,
        'coins': 0,
        'householdId': householdId,
      });
    });
    test('approving a completed task contributes its XP reward to an active xpEarned goal', () async {
      final now = DateTime.now();

      final goalRef = firestore
          .collection('households')
          .doc(householdId)
          .collection('goals')
          .doc('xp-goal');

      final goal = Goal(
        id: 'xp-goal',
        title: 'Earn 200 XP',
        type: GoalType.family,
        metric: GoalMetric.xpEarned,
        period: GoalPeriod.weekly,
        targetValue: 200,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 6)),
      );

      await goalRef.set(goal.toFirestore());

      const task = TaskModel(
        id: 'task-1',
        title: 'Clean Your Room',
        assignedToUserId: childId,
        rewardXp: 50,
        coinReward: 10,
        status: TaskStatus.completed,
      );

      await databaseService.addTask(task);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = taskSnapshot.docs.first.id;

      await databaseService.approveTask(taskId);

      final updatedGoal = await goalRef.get();

      expect(updatedGoal.data()?['currentProgress'], 50);

      final contribution = await goalRef
          .collection('contributions')
          .doc(taskId)
          .get();

      expect(contribution.exists, isTrue);
      expect(contribution.data()?['userId'], childId);
      expect(contribution.data()?['amount'], 50);
      expect(contribution.data()?['activityType'], 'taskApproval');
    });

    test('approving a completed task contributes its coin reward to an active coinsEarned goal', () async {
      final now = DateTime.now();

      final goalRef = firestore
          .collection('households')
          .doc(householdId)
          .collection('goals')
          .doc('coins-goal');

      final goal = Goal(
        id: 'coins-goal',
        title: 'Earn 100 Coins',
        type: GoalType.family,
        metric: GoalMetric.coinsEarned,
        period: GoalPeriod.weekly,
        targetValue: 100,
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 6)),
      );

      await goalRef.set(goal.toFirestore());

      const task = TaskModel(
        id: 'task-1',
        title: 'Wash the Dishes',
        assignedToUserId: childId,
        rewardXp: 50,
        coinReward: 15,
        status: TaskStatus.completed,
      );

      await databaseService.addTask(task);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = taskSnapshot.docs.first.id;

      await databaseService.approveTask(taskId);

      final updatedGoal = await goalRef.get();

      expect(updatedGoal.data()?['currentProgress'], 15);

      final contribution = await goalRef
          .collection('contributions')
          .doc(taskId)
          .get();

      expect(contribution.exists, isTrue);
      expect(contribution.data()?['userId'], childId);
      expect(contribution.data()?['amount'], 15);
      expect(contribution.data()?['activityType'], 'taskApproval');
    });

    test(
      'approving the same task twice does not contribute to a goal twice',
      () async {
        final now = DateTime.now();

        final goalRef = firestore
            .collection('households')
            .doc(householdId)
            .collection('goals')
            .doc('goal-1');

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 5 Tasks',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
        );

        await goalRef.set(goal.toFirestore());

        const task = TaskModel(
          id: 'task-1',
          title: 'Feed the Dog',
          assignedToUserId: childId,
          rewardXp: 50,
          coinReward: 10,
          status: TaskStatus.completed,
        );

        await databaseService.addTask(task);

        final taskSnapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = taskSnapshot.docs.first.id;

        await databaseService.approveTask(taskId);
        await databaseService.approveTask(taskId);

        final updatedGoal = await goalRef.get();

        expect(updatedGoal.data()?['currentProgress'], 1);

        final contributions = await goalRef.collection('contributions').get();

        expect(contributions.docs, hasLength(1));
        expect(contributions.docs.first.id, taskId);
      },
    );

    test(
      'approving a task only contributes to goals in the active household',
      () async {
        final now = DateTime.now();
        const secondHouseholdId = 'household-2';

        await firestore.collection('households').doc(secondHouseholdId).set({
          'name': 'Second Household',
          'ownerId': 'parent-2',
          'memberIds': ['parent-2', childId],
        });

        final householdAGoalRef = firestore
            .collection('households')
            .doc(householdId)
            .collection('goals')
            .doc('household-a-goal');

        final householdBGoalRef = firestore
            .collection('households')
            .doc(secondHouseholdId)
            .collection('goals')
            .doc('household-b-goal');

        final householdAGoal = Goal(
          id: 'household-a-goal',
          title: 'Household A Tasks',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
        );

        final householdBGoal = Goal(
          id: 'household-b-goal',
          title: 'Household B Tasks',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
        );

        await householdAGoalRef.set(householdAGoal.toFirestore());
        await householdBGoalRef.set(householdBGoal.toFirestore());

        const task = TaskModel(
          id: 'task-1',
          title: 'Clean the Kitchen',
          assignedToUserId: childId,
          rewardXp: 50,
          coinReward: 10,
          status: TaskStatus.completed,
        );

        // DatabaseService is currently bound to household-1.
        await databaseService.addTask(task);

        final taskSnapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = taskSnapshot.docs.first.id;

        await databaseService.approveTask(taskId);

        final updatedHouseholdAGoal = await householdAGoalRef.get();
        final updatedHouseholdBGoal = await householdBGoalRef.get();

        expect(updatedHouseholdAGoal.data()?['currentProgress'], 1);
        expect(updatedHouseholdBGoal.data()?['currentProgress'], 0);

        final householdBContribution = await householdBGoalRef
            .collection('contributions')
            .doc(taskId)
            .get();

        expect(householdBContribution.exists, isFalse);
      },
    );

    test('approving a task does not contribute to an individual goal when the child is not a participant', () async {
      final now = DateTime.now();
      const otherChildId = 'child-2';

      // Add another child to the household.
      await firestore.collection('households').doc(householdId).update({
        'memberIds': ['parent-1', childId, otherChildId],
      });

      await firestore.collection('users').doc(otherChildId).set({
        'xp': 0,
        'coins': 0,
        'householdId': householdId,
      });

      // This individual goal belongs to child-2, not child-1.
      final goalRef = firestore
          .collection('households')
          .doc(householdId)
          .collection('goals')
          .doc('individual-goal');

      final goal = Goal(
        id: 'individual-goal',
        title: 'Complete 5 Tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: [otherChildId],
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 6)),
      );

      await goalRef.set(goal.toFirestore());

      // child-1 completes the task.
      const task = TaskModel(
        id: 'task-1',
        title: 'Take Out the Trash',
        assignedToUserId: childId,
        rewardXp: 50,
        coinReward: 10,
        status: TaskStatus.completed,
      );

      await databaseService.addTask(task);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = taskSnapshot.docs.first.id;

      await databaseService.approveTask(taskId);

      final updatedGoal = await goalRef.get();

      // child-1 was not a participant, so the goal must remain unchanged.
      expect(updatedGoal.data()?['currentProgress'], 0);

      // No contribution should have been created for this task.
      final contribution = await goalRef
          .collection('contributions')
          .doc(taskId)
          .get();

      expect(contribution.exists, isFalse);
    });

    test('approving a task contributes to an individual goal when the child is a participant', () async {
      final now = DateTime.now();

      final goalRef = firestore
          .collection('households')
          .doc(householdId)
          .collection('goals')
          .doc('individual-goal');

      // This individual goal explicitly belongs to child-1.
      final goal = Goal(
        id: 'individual-goal',
        title: 'Complete 5 Tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: [childId],
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 6)),
      );

      await goalRef.set(goal.toFirestore());

      const task = TaskModel(
        id: 'task-1',
        title: 'Make the Bed',
        assignedToUserId: childId,
        rewardXp: 50,
        coinReward: 10,
        status: TaskStatus.completed,
      );

      await databaseService.addTask(task);

      final taskSnapshot = await firestore
          .collection('households')
          .doc(householdId)
          .collection('tasks')
          .get();

      final taskId = taskSnapshot.docs.first.id;

      await databaseService.approveTask(taskId);

      final updatedGoal = await goalRef.get();

      // child-1 is an eligible participant, so the goal should progress.
      expect(updatedGoal.data()?['currentProgress'], 1);

      final contribution = await goalRef
          .collection('contributions')
          .doc(taskId)
          .get();

      expect(contribution.exists, isTrue);
      expect(contribution.data()?['userId'], childId);
      expect(contribution.data()?['amount'], 1);
      expect(contribution.data()?['activityType'], 'taskApproval');
    });
    test(
      'approving a completed task contributes to an active tasksCompleted goal',
      () async {
        final now = DateTime.now();

        final goalRef = firestore
            .collection('households')
            .doc(householdId)
            .collection('goals')
            .doc('goal-1');

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 5 Tasks',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          startsAt: now.subtract(const Duration(days: 1)),
          endsAt: now.add(const Duration(days: 6)),
        );

        await goalRef.set(goal.toFirestore());

        const task = TaskModel(
          id: 'task-1',
          title: 'Feed the Dog',
          assignedToUserId: childId,
          rewardXp: 50,
          coinReward: 10,
          status: TaskStatus.completed,
        );

        await databaseService.addTask(task);

        final taskSnapshot = await firestore
            .collection('households')
            .doc(householdId)
            .collection('tasks')
            .get();

        final taskId = taskSnapshot.docs.first.id;

        await databaseService.approveTask(taskId);

        final updatedGoal = await goalRef.get();

        expect(updatedGoal.data()?['currentProgress'], 1);

        final contribution = await goalRef
            .collection('contributions')
            .doc(taskId)
            .get();

        expect(contribution.exists, isTrue);
        expect(contribution.data()?['userId'], childId);
        expect(contribution.data()?['amount'], 1);
        expect(contribution.data()?['activityType'], 'taskApproval');
        expect(contribution.data()?['recordedAt'], isA<Timestamp>());
      },
    );
  });
}
