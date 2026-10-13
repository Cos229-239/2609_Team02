import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:famotive/core/models/task.dart';
import 'package:famotive/core/models/goal.dart';
import 'package:famotive/core/models/goal_contribution.dart';
import 'package:famotive/core/services/goal_service.dart';

void main() {
  group('GoalService', () {
    late FakeFirebaseFirestore firestore;
    late GoalService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GoalService(firestore: firestore);
    });

    test(
      'records an eligible contribution and updates goal progress',
      () async {
        final startsAt = DateTime(2026, 10, 1);
        final endsAt = DateTime(2026, 10, 8);
        final recordedAt = DateTime(2026, 10, 3);

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 5 tasks',
          type: GoalType.individual,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          participantIds: const ['child-1'],
          startsAt: startsAt,
          endsAt: endsAt,
        );

        await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .set(goal.toFirestore());

        final contribution = GoalContribution(
          activityId: 'task-123',
          userId: 'child-1',
          amount: 1,
          activityType: GoalActivityType.taskApproval,
          recordedAt: recordedAt,
        );

        final recorded = await service.recordContribution(
          householdId: 'household-1',
          goalId: goal.id,
          contribution: contribution,
        );

        expect(recorded, isTrue);

        final goalSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .get();

        expect(goalSnapshot.data()?['currentProgress'], 1);

        final contributionSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .collection('contributions')
            .doc('task-123')
            .get();

        expect(contributionSnapshot.exists, isTrue);
        expect(contributionSnapshot.data()?['userId'], 'child-1');
        expect(contributionSnapshot.data()?['amount'], 1);
        expect(contributionSnapshot.data()?['activityType'], 'taskApproval');
      },
    );

    test('does not count the same activity more than once', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3);

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-123',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final firstResult = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      final secondResult = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(firstResult, isTrue);
      expect(secondResult, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 1);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .get();

      expect(contributionSnapshot.docs.length, 1);
    });

    test(
      'marks a goal complete when contribution reaches the target',
      () async {
        final startsAt = DateTime(2026, 10, 1);
        final endsAt = DateTime(2026, 10, 8);
        final recordedAt = DateTime(2026, 10, 3, 14, 30);

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 5 tasks',
          type: GoalType.individual,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          currentProgress: 4,
          participantIds: const ['child-1'],
          startsAt: startsAt,
          endsAt: endsAt,
        );

        await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .set(goal.toFirestore());

        final contribution = GoalContribution(
          activityId: 'task-555',
          userId: 'child-1',
          amount: 1,
          activityType: GoalActivityType.taskApproval,
          recordedAt: recordedAt,
        );

        final recorded = await service.recordContribution(
          householdId: 'household-1',
          goalId: goal.id,
          contribution: contribution,
        );

        expect(recorded, isTrue);

        final goalSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .get();

        final updatedGoal = Goal.fromFirestore(goalSnapshot);

        expect(updatedGoal.currentProgress, 5);
        expect(updatedGoal.isCompleted, isTrue);
        expect(updatedGoal.completedAt, recordedAt);
      },
    );

    test('does not increase goal progress beyond the target', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3, 14, 30);

      final goal = Goal(
        id: 'goal-1',
        title: 'Earn 500 XP',
        type: GoalType.individual,
        metric: GoalMetric.xpEarned,
        period: GoalPeriod.weekly,
        targetValue: 500,
        currentProgress: 450,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-456',
        userId: 'child-1',
        amount: 100,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isTrue);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      final updatedGoal = Goal.fromFirestore(goalSnapshot);

      expect(updatedGoal.currentProgress, 500);
      expect(updatedGoal.isCompleted, isTrue);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-456')
          .get();

      expect(contributionSnapshot.data()?['amount'], 100);
    });

    test(
      'rejects contribution from non-participant in individual goal',
      () async {
        final startsAt = DateTime(2026, 10, 1);
        final endsAt = DateTime(2026, 10, 8);
        final recordedAt = DateTime(2026, 10, 3);

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 5 tasks',
          type: GoalType.individual,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          participantIds: const ['child-1'],
          startsAt: startsAt,
          endsAt: endsAt,
        );

        await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .set(goal.toFirestore());

        final contribution = GoalContribution(
          activityId: 'task-999',
          userId: 'child-2',
          amount: 1,
          activityType: GoalActivityType.taskApproval,
          recordedAt: recordedAt,
        );

        final recorded = await service.recordContribution(
          householdId: 'household-1',
          goalId: goal.id,
          contribution: contribution,
        );

        expect(recorded, isFalse);

        final goalSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .get();

        expect(goalSnapshot.data()?['currentProgress'], 0);

        final contributionSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .collection('contributions')
            .doc('task-999')
            .get();

        expect(contributionSnapshot.exists, isFalse);
      },
    );

    test(
      'allows multiple team participants to contribute to shared progress',
      () async {
        final startsAt = DateTime(2026, 10, 1);
        final endsAt = DateTime(2026, 10, 8);

        final goal = Goal(
          id: 'goal-1',
          title: 'Complete 10 tasks together',
          type: GoalType.team,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 10,
          participantIds: const ['child-1', 'child-2'],
          startsAt: startsAt,
          endsAt: endsAt,
        );

        await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .set(goal.toFirestore());

        final firstContribution = GoalContribution(
          activityId: 'task-101',
          userId: 'child-1',
          amount: 1,
          activityType: GoalActivityType.taskApproval,
          recordedAt: DateTime(2026, 10, 3, 10),
        );

        final secondContribution = GoalContribution(
          activityId: 'task-102',
          userId: 'child-2',
          amount: 1,
          activityType: GoalActivityType.taskApproval,
          recordedAt: DateTime(2026, 10, 3, 11),
        );

        final firstRecorded = await service.recordContribution(
          householdId: 'household-1',
          goalId: goal.id,
          contribution: firstContribution,
        );

        final secondRecorded = await service.recordContribution(
          householdId: 'household-1',
          goalId: goal.id,
          contribution: secondContribution,
        );

        expect(firstRecorded, isTrue);
        expect(secondRecorded, isTrue);

        final goalSnapshot = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .get();

        expect(goalSnapshot.data()?['currentProgress'], 2);

        final contributions = await firestore
            .collection('households')
            .doc('household-1')
            .collection('goals')
            .doc(goal.id)
            .collection('contributions')
            .get();

        expect(contributions.docs.length, 2);

        final contributorIds = contributions.docs
            .map((doc) => doc.data()['userId'])
            .toSet();

        expect(contributorIds, {'child-1', 'child-2'});
      },
    );

    test('rejects contribution from user outside team participants', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3);

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 10 tasks together',
        type: GoalType.team,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 10,
        participantIds: const ['child-1', 'child-2'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-103',
        userId: 'child-3',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 0);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-103')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('allows household member to contribute to family goal', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3);

      await firestore.collection('households').doc('household-1').set({
        'name': 'Test Family',
        'memberIds': ['parent-1', 'child-1', 'child-2'],
        'ownerId': 'parent-1',
      });

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 20 tasks as a family',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 20,
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-201',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isTrue);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 1);
    });

    test('rejects non-household member from family goal', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3);

      await firestore.collection('households').doc('household-1').set({
        'name': 'Test Family',
        'memberIds': ['parent-1', 'child-1', 'child-2'],
        'ownerId': 'parent-1',
      });

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 20 tasks as a family',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 20,
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-outsider',
        userId: 'not-a-member',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 0);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-outsider')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('rejects contribution to an already completed goal', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final completedAt = DateTime(2026, 10, 2);
      final recordedAt = DateTime(2026, 10, 3);

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        currentProgress: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
        completedAt: completedAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-after-completion',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      final updatedGoal = Goal.fromFirestore(goalSnapshot);

      expect(updatedGoal.currentProgress, 5);
      expect(updatedGoal.completedAt, completedAt);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-after-completion')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('rejects contribution before goal starts', () async {
      final startsAt = DateTime(2026, 10, 3);
      final endsAt = DateTime(2026, 10, 10);

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-before-start',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: DateTime(2026, 10, 2),
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 0);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-before-start')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('rejects contribution at or after goal end', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);

      final goal = Goal(
        id: 'goal-1',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .set(goal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-at-end',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: endsAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: goal.id,
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final goalSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .get();

      expect(goalSnapshot.data()?['currentProgress'], 0);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc(goal.id)
          .collection('contributions')
          .doc('task-at-end')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('returns false when goal does not exist', () async {
      final contribution = GoalContribution(
        activityId: 'task-404',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: DateTime(2026, 10, 3),
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: 'missing-goal',
        contribution: contribution,
      );

      expect(recorded, isFalse);

      final contributionSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc('missing-goal')
          .collection('contributions')
          .doc('task-404')
          .get();

      expect(contributionSnapshot.exists, isFalse);
    });

    test('updates only the specified household goal', () async {
      final startsAt = DateTime(2026, 10, 1);
      final endsAt = DateTime(2026, 10, 8);
      final recordedAt = DateTime(2026, 10, 3);

      final householdOneGoal = Goal(
        id: 'shared-goal-id',
        title: 'Household One Goal',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      final householdTwoGoal = Goal(
        id: 'shared-goal-id',
        title: 'Household Two Goal',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc('shared-goal-id')
          .set(householdOneGoal.toFirestore());

      await firestore
          .collection('households')
          .doc('household-2')
          .collection('goals')
          .doc('shared-goal-id')
          .set(householdTwoGoal.toFirestore());

      final contribution = GoalContribution(
        activityId: 'task-301',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final recorded = await service.recordContribution(
        householdId: 'household-1',
        goalId: 'shared-goal-id',
        contribution: contribution,
      );

      expect(recorded, isTrue);

      final householdOneSnapshot = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc('shared-goal-id')
          .get();

      final householdTwoSnapshot = await firestore
          .collection('households')
          .doc('household-2')
          .collection('goals')
          .doc('shared-goal-id')
          .get();

      expect(householdOneSnapshot.data()?['currentProgress'], 1);
      expect(householdTwoSnapshot.data()?['currentProgress'], 0);

      final householdOneContribution = await firestore
          .collection('households')
          .doc('household-1')
          .collection('goals')
          .doc('shared-goal-id')
          .collection('contributions')
          .doc('task-301')
          .get();

      final householdTwoContribution = await firestore
          .collection('households')
          .doc('household-2')
          .collection('goals')
          .doc('shared-goal-id')
          .collection('contributions')
          .doc('task-301')
          .get();

      expect(householdOneContribution.exists, isTrue);
      expect(householdTwoContribution.exists, isFalse);
    });

    group('Challenge creation and task association', () {
      test('creates a goal and links only the selected tasks', () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);
        final tasksRef = householdRef.collection('tasks');

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1'],
        });

        for (final taskId in ['task-1', 'task-2', 'task-3']) {
          await tasksRef
              .doc(taskId)
              .set(TaskModel(id: taskId, title: 'Task $taskId').toFirestore());
        }

        final goal = Goal(
          id: '',
          title: 'Kitchen Cleanup Week',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 2,
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        final goalId = await service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1', 'task-2'],
        );

        final savedGoal = await householdRef
            .collection('goals')
            .doc(goalId)
            .get();

        final task1 = await tasksRef.doc('task-1').get();
        final task2 = await tasksRef.doc('task-2').get();
        final task3 = await tasksRef.doc('task-3').get();

        expect(savedGoal.exists, isTrue);
        expect(savedGoal.data()?['title'], 'Kitchen Cleanup Week');
        expect(savedGoal.data()?['currentProgress'], 0);

        expect(task1.data()?['goalId'], goalId);
        expect(task2.data()?['goalId'], goalId);

        // Unselected tasks must remain regular household tasks.
        expect(task3.data()?['goalId'], isNull);
      });
    });

    test('does not create a goal when a selected task is invalid', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(id: 'task-1', title: 'Wash Dishes').toFirestore(),
          );

      await tasksRef
          .doc('task-2')
          .set(
            const TaskModel(
              id: 'task-2',
              title: 'Wipe Counters',
              status: TaskStatus.approved,
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Kitchen Cleanup Week',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      await expectLater(
        service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1', 'task-2'],
        ),
        throwsStateError,
      );

      final goalsSnapshot = await householdRef.collection('goals').get();
      final validTaskSnapshot = await tasksRef.doc('task-1').get();
      final invalidTaskSnapshot = await tasksRef.doc('task-2').get();

      // The transaction must not partially create the challenge.
      expect(goalsSnapshot.docs, isEmpty);
      expect(validTaskSnapshot.data()?['goalId'], isNull);
      expect(invalidTaskSnapshot.data()?['goalId'], isNull);
    });

    test('rejects a task already linked to another challenge', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(
              id: 'task-1',
              title: 'Wash Dishes',
              goalId: 'existing-goal',
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Kitchen Cleanup Week',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      await expectLater(
        service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1'],
        ),
        throwsStateError,
      );

      final goalsSnapshot = await householdRef.collection('goals').get();
      final taskSnapshot = await tasksRef.doc('task-1').get();

      expect(goalsSnapshot.docs, isEmpty);
      expect(taskSnapshot.data()?['goalId'], 'existing-goal');
    });

    for (final invalidTask in [
      const TaskModel(
        id: 'invalid-task',
        title: 'Awaiting Approval',
        status: TaskStatus.completed,
      ),
      const TaskModel(
        id: 'invalid-task',
        title: 'Archived Task',
        archived: true,
      ),
    ]) {
      test('rejects ineligible task: ${invalidTask.title}', () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);
        final tasksRef = householdRef.collection('tasks');

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1'],
        });

        await tasksRef.doc(invalidTask.id).set(invalidTask.toFirestore());

        final goal = Goal(
          id: '',
          title: 'Kitchen Cleanup Week',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 2,
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: goal,
            taskIds: [invalidTask.id],
          ),
          throwsStateError,
        );

        final goals = await householdRef.collection('goals').get();
        final task = await tasksRef.doc(invalidTask.id).get();

        expect(goals.docs, isEmpty);
        expect(task.data()?['goalId'], isNull);
      });
    }

    test(
      'rejects a missing task without creating a partial challenge',
      () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);
        final tasksRef = householdRef.collection('tasks');

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1'],
        });

        await tasksRef
            .doc('task-1')
            .set(
              const TaskModel(id: 'task-1', title: 'Wash Dishes').toFirestore(),
            );

        final goal = Goal(
          id: '',
          title: 'Kitchen Cleanup Week',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 2,
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: goal,
            taskIds: ['task-1', 'deleted-task'],
          ),
          throwsStateError,
        );

        final goals = await householdRef.collection('goals').get();
        final validTask = await tasksRef.doc('task-1').get();

        expect(goals.docs, isEmpty);
        expect(validTask.data()?['goalId'], isNull);
      },
    );

    for (final invalidGoal in [
      Goal(
        id: '',
        title: '   ',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      ),
      Goal(
        id: '',
        title: 'Invalid Target',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 0,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      ),
      Goal(
        id: '',
        title: 'Invalid Dates',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 19),
        endsAt: DateTime(2026, 10, 12),
      ),
      Goal(
        id: '',
        title: 'Individual Without Participant',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      ),
      Goal(
        id: '',
        title: 'Team Without Enough Participants',
        type: GoalType.team,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        participantIds: const ['child-1'],
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      ),
    ]) {
      test('rejects invalid goal: ${invalidGoal.title}', () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1'],
        });

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: invalidGoal,
            taskIds: const [],
          ),
          throwsStateError,
        );

        final goals = await householdRef.collection('goals').get();
        expect(goals.docs, isEmpty);
      });
    }

    test('rejects duplicate task IDs without creating a challenge', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(id: 'task-1', title: 'Wash Dishes').toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Kitchen Cleanup Week',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      await expectLater(
        service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1', 'task-1'],
        ),
        throwsStateError,
      );

      final goals = await householdRef.collection('goals').get();
      final task = await tasksRef.doc('task-1').get();

      expect(goals.docs, isEmpty);
      expect(task.data()?['goalId'], isNull);
    });

    test(
      'rejects a challenge with participants outside the household',
      () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1', 'child-2'],
        });

        final goal = Goal(
          id: '',
          title: 'Team Cleanup Challenge',
          type: GoalType.team,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 5,
          participantIds: const ['child-1', 'child-99'],
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: goal,
            taskIds: const [],
          ),
          throwsStateError,
        );

        final goals = await householdRef.collection('goals').get();
        expect(goals.docs, isEmpty);
      },
    );

    test('rejects tasks assigned outside the challenge participants', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1', 'child-2'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(
              id: 'task-1',
              title: 'Clean Bedroom',
              assignedToUserId: 'child-2',
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Bedroom Challenge',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 3,
        participantIds: const ['child-1'],
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      await expectLater(
        service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1'],
        ),
        throwsStateError,
      );

      final goals = await householdRef.collection('goals').get();
      final task = await tasksRef.doc('task-1').get();

      expect(goals.docs, isEmpty);
      expect(task.data()?['goalId'], isNull);
    });

    test('allows unclaimed tasks in an individual challenge', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(
              id: 'task-1',
              title: 'Take Out Trash',
              assignedToUserId: null,
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Weekly Responsibility Challenge',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 3,
        participantIds: const ['child-1'],
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      final goalId = await service.createGoalWithTasks(
        householdId: householdId,
        goal: goal,
        taskIds: ['task-1'],
      );

      final savedGoal = await householdRef
          .collection('goals')
          .doc(goalId)
          .get();
      final task = await tasksRef.doc('task-1').get();

      expect(savedGoal.exists, isTrue);
      expect(task.data()?['goalId'], goalId);
      expect(task.data()?['assignedToUserId'], isNull);
    });

    test(
      'rejects challenge creation when the household does not exist',
      () async {
        const householdId = 'missing-household';

        final goal = Goal(
          id: '',
          title: 'Weekly Cleanup Challenge',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 3,
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: goal,
            taskIds: const [],
          ),
          throwsStateError,
        );

        final householdRef = firestore
            .collection('households')
            .doc(householdId);

        final goals = await householdRef.collection('goals').get();

        expect(goals.docs, isEmpty);
      },
    );

    test('creates new tasks alongside selected existing tasks', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('existing-task')
          .set(
            const TaskModel(
              id: 'existing-task',
              title: 'Wash Dishes',
              assignedToUserId: 'child-1',
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Weekend House Cleanup',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      final goalId = await service.createGoalWithTasks(
        householdId: householdId,
        goal: goal,
        taskIds: ['existing-task'],
        newTasks: const [
          TaskModel(
            id: '',
            title: 'Organize Pantry',
            assignedToUserId: 'child-1',
          ),
        ],
      );

      final savedGoal = await householdRef
          .collection('goals')
          .doc(goalId)
          .get();
      final allTasks = await tasksRef.get();

      expect(savedGoal.exists, isTrue);
      expect(allTasks.docs.length, 2);

      final existingTask = await tasksRef.doc('existing-task').get();
      expect(existingTask.data()?['goalId'], goalId);

      final newTask = allTasks.docs.singleWhere(
        (doc) => doc.id != 'existing-task',
      );

      expect(newTask.data()['title'], 'Organize Pantry');
      expect(newTask.data()['assignedToUserId'], 'child-1');
      expect(newTask.data()['goalId'], goalId);
      expect(newTask.data()['status'], TaskStatus.pending.name);
    });

    test(
      'rejects an invalid new task without saving partial changes',
      () async {
        const householdId = 'household-1';

        final householdRef = firestore
            .collection('households')
            .doc(householdId);
        final tasksRef = householdRef.collection('tasks');

        await householdRef.set({
          'name': 'Test Household',
          'ownerId': 'parent-1',
          'memberIds': ['parent-1', 'child-1'],
        });

        await tasksRef
            .doc('existing-task')
            .set(
              const TaskModel(
                id: 'existing-task',
                title: 'Wash Dishes',
              ).toFirestore(),
            );

        final goal = Goal(
          id: '',
          title: 'Weekend House Cleanup',
          type: GoalType.family,
          metric: GoalMetric.tasksCompleted,
          period: GoalPeriod.weekly,
          targetValue: 2,
          startsAt: DateTime(2026, 10, 12),
          endsAt: DateTime(2026, 10, 19),
        );

        await expectLater(
          service.createGoalWithTasks(
            householdId: householdId,
            goal: goal,
            taskIds: ['existing-task'],
            newTasks: const [
              TaskModel(id: '', title: '   ', assignedToUserId: 'child-1'),
            ],
          ),
          throwsStateError,
        );

        final goals = await householdRef.collection('goals').get();
        final tasks = await tasksRef.get();
        final existingTask = await tasksRef.doc('existing-task').get();

        expect(goals.docs, isEmpty);
        expect(tasks.docs.length, 1);
        expect(existingTask.data()?['goalId'], isNull);
      },
    );

    test('rejects existing tasks assigned outside the household', () async {
      const householdId = 'household-1';

      final householdRef = firestore.collection('households').doc(householdId);
      final tasksRef = householdRef.collection('tasks');

      await householdRef.set({
        'name': 'Test Household',
        'ownerId': 'parent-1',
        'memberIds': ['parent-1', 'child-1'],
      });

      await tasksRef
          .doc('task-1')
          .set(
            const TaskModel(
              id: 'task-1',
              title: 'Clean Garage',
              assignedToUserId: 'outsider-1',
            ).toFirestore(),
          );

      final goal = Goal(
        id: '',
        title: 'Family Cleanup',
        type: GoalType.family,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 2,
        startsAt: DateTime(2026, 10, 12),
        endsAt: DateTime(2026, 10, 19),
      );

      await expectLater(
        service.createGoalWithTasks(
          householdId: householdId,
          goal: goal,
          taskIds: ['task-1'],
        ),
        throwsStateError,
      );

      final goals = await householdRef.collection('goals').get();
      final task = await tasksRef.doc('task-1').get();

      expect(goals.docs, isEmpty);
      expect(task.data()?['goalId'], isNull);
    });
  });
}
