import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/goal.dart';

void main() {
  group('Goal', () {
    final startsAt = DateTime(2026, 10, 1);
    final endsAt = DateTime(2026, 10, 8);

    test('creates an individual goal with expected values', () {
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

      expect(goal.id, 'goal-1');
      expect(goal.title, 'Complete 5 tasks');
      expect(goal.type, GoalType.individual);
      expect(goal.metric, GoalMetric.tasksCompleted);
      expect(goal.period, GoalPeriod.weekly);
      expect(goal.targetValue, 5);
      expect(goal.currentProgress, 0);
      expect(goal.participantIds, ['child-1']);
      expect(goal.startsAt, startsAt);
      expect(goal.endsAt, endsAt);
      expect(goal.completedAt, isNull);
      expect(goal.isCompleted, isFalse);
    });

    test('supports family goals without explicit participants', () {
      final goal = Goal(
        id: 'goal-2',
        title: 'Earn 500 XP',
        type: GoalType.family,
        metric: GoalMetric.xpEarned,
        period: GoalPeriod.weekly,
        targetValue: 500,
        startsAt: startsAt,
        endsAt: endsAt,
      );

      expect(goal.type, GoalType.family);
      expect(goal.participantIds, isEmpty);
    });

    test('supports team goals with multiple participants', () {
      final goal = Goal(
        id: 'goal-3',
        title: 'Earn 100 Coins',
        type: GoalType.team,
        metric: GoalMetric.coinsEarned,
        period: GoalPeriod.weekly,
        targetValue: 100,
        participantIds: const ['child-1', 'child-2'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      expect(goal.type, GoalType.team);
      expect(goal.participantIds, ['child-1', 'child-2']);
    });

    test('isCompleted is true when completedAt exists', () {
      final completedAt = DateTime(2026, 10, 4);

      final goal = Goal(
        id: 'goal-4',
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

      expect(goal.isCompleted, isTrue);
      expect(goal.completedAt, completedAt);
    });

    test('isActiveAt is true during the goal period', () {
      final goal = Goal(
        id: 'goal-5',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      expect(goal.isActiveAt(DateTime(2026, 10, 4)), isTrue);
    });

    test('isActiveAt is false before the goal period', () {
      final goal = Goal(
        id: 'goal-6',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      expect(goal.isActiveAt(DateTime(2026, 9, 30)), isFalse);
    });

    test('isActiveAt is false after the goal period', () {
      final goal = Goal(
        id: 'goal-7',
        title: 'Complete 5 tasks',
        type: GoalType.individual,
        metric: GoalMetric.tasksCompleted,
        period: GoalPeriod.weekly,
        targetValue: 5,
        participantIds: const ['child-1'],
        startsAt: startsAt,
        endsAt: endsAt,
      );

      expect(goal.isActiveAt(DateTime(2026, 10, 9)), isFalse);
    });

    test('toFirestore serializes goal fields', () {
      final goal = Goal(
        id: 'goal-8',
        title: 'Earn 500 XP',
        type: GoalType.family,
        metric: GoalMetric.xpEarned,
        period: GoalPeriod.weekly,
        targetValue: 500,
        currentProgress: 150,
        startsAt: startsAt,
        endsAt: endsAt,
      );

      final data = goal.toFirestore();

      expect(data['title'], 'Earn 500 XP');
      expect(data['type'], 'family');
      expect(data['metric'], 'xpEarned');
      expect(data['period'], 'weekly');
      expect(data['targetValue'], 500);
      expect(data['currentProgress'], 150);
      expect(data['participantIds'], isEmpty);
      expect(data['startsAt'], Timestamp.fromDate(startsAt));
      expect(data['endsAt'], Timestamp.fromDate(endsAt));
      expect(data['completedAt'], isNull);
    });

    test('fromFirestore deserializes goal fields', () async {
  final firestore = FakeFirebaseFirestore();

  final completedAt = DateTime(2026, 10, 5);

  await firestore.collection('goals').doc('goal-9').set({
    'title': 'Complete 10 Tasks',
    'type': 'team',
    'metric': 'tasksCompleted',
    'period': 'weekly',
    'targetValue': 10,
    'currentProgress': 6,
    'participantIds': ['child-1', 'child-2'],
    'startsAt': Timestamp.fromDate(startsAt),
    'endsAt': Timestamp.fromDate(endsAt),
    'completedAt': Timestamp.fromDate(completedAt),
  });

  final snapshot =
      await firestore.collection('goals').doc('goal-9').get();

  final goal = Goal.fromFirestore(snapshot);

  expect(goal.id, 'goal-9');
  expect(goal.title, 'Complete 10 Tasks');
  expect(goal.type, GoalType.team);
  expect(goal.metric, GoalMetric.tasksCompleted);
  expect(goal.period, GoalPeriod.weekly);
  expect(goal.targetValue, 10);
  expect(goal.currentProgress, 6);
  expect(goal.participantIds, ['child-1', 'child-2']);
  expect(goal.startsAt, startsAt);
  expect(goal.endsAt, endsAt);
  expect(goal.completedAt, completedAt);
  expect(goal.isCompleted, isTrue);
});

test('fromFirestore uses safe defaults for unknown enum values', () async {
  final firestore = FakeFirebaseFirestore();

  await firestore.collection('goals').doc('goal-10').set({
    'title': 'Legacy Goal',
    'type': 'unknown-type',
    'metric': 'unknown-metric',
    'period': 'unknown-period',
    'targetValue': 5,
    'startsAt': Timestamp.fromDate(startsAt),
    'endsAt': Timestamp.fromDate(endsAt),
  });

  final snapshot =
      await firestore.collection('goals').doc('goal-10').get();

  final goal = Goal.fromFirestore(snapshot);

  expect(goal.type, GoalType.individual);
  expect(goal.metric, GoalMetric.tasksCompleted);
  expect(goal.period, GoalPeriod.weekly);
  expect(goal.currentProgress, 0);
  expect(goal.participantIds, isEmpty);
  expect(goal.completedAt, isNull);
});
  });
}