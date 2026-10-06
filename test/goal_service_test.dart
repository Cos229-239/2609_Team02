import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
