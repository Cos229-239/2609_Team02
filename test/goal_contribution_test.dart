import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:famotive/core/models/goal_contribution.dart';

void main() {
  group('GoalContribution', () {
    final recordedAt = DateTime(2026, 10, 3, 12, 30);

    test('creates a task approval contribution with expected values', () {
      final contribution = GoalContribution(
        activityId: 'task-123',
        userId: 'child-1',
        amount: 1,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      expect(contribution.activityId, 'task-123');
      expect(contribution.userId, 'child-1');
      expect(contribution.amount, 1);
      expect(contribution.activityType, GoalActivityType.taskApproval);
      expect(contribution.recordedAt, recordedAt);
    });

    test('supports contribution amounts greater than one', () {
      final contribution = GoalContribution(
        activityId: 'task-456',
        userId: 'child-1',
        amount: 50,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      expect(contribution.amount, 50);
    });

    test('toFirestore serializes contribution fields', () {
      final contribution = GoalContribution(
        activityId: 'task-789',
        userId: 'child-2',
        amount: 25,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final data = contribution.toFirestore();

      expect(data['userId'], 'child-2');
      expect(data['amount'], 25);
      expect(data['activityType'], 'taskApproval');
      expect(data['recordedAt'], Timestamp.fromDate(recordedAt));
    });

    test('toFirestore does not duplicate activityId in document data', () {
      final contribution = GoalContribution(
        activityId: 'task-789',
        userId: 'child-2',
        amount: 25,
        activityType: GoalActivityType.taskApproval,
        recordedAt: recordedAt,
      );

      final data = contribution.toFirestore();

      expect(data.containsKey('activityId'), isFalse);
    });

    test('fromFirestore deserializes contribution fields', () async {
      final firestore = FakeFirebaseFirestore();

      await firestore
          .collection('contributions')
          .doc('task-123')
          .set({
        'userId': 'child-1',
        'amount': 50,
        'activityType': 'taskApproval',
        'recordedAt': Timestamp.fromDate(recordedAt),
      });

      final snapshot = await firestore
          .collection('contributions')
          .doc('task-123')
          .get();

      final contribution = GoalContribution.fromFirestore(snapshot);

      expect(contribution.activityId, 'task-123');
      expect(contribution.userId, 'child-1');
      expect(contribution.amount, 50);
      expect(contribution.activityType, GoalActivityType.taskApproval);
      expect(contribution.recordedAt, recordedAt);
    });

    test('fromFirestore uses safe defaults for missing or unknown values',
        () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('contributions').doc('task-999').set({
        'activityType': 'unknown-type',
      });

      final snapshot = await firestore
          .collection('contributions')
          .doc('task-999')
          .get();

      final contribution = GoalContribution.fromFirestore(snapshot);

      expect(contribution.activityId, 'task-999');
      expect(contribution.userId, '');
      expect(contribution.amount, 0);
      expect(contribution.activityType, GoalActivityType.taskApproval);
      expect(
        contribution.recordedAt,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
  });
}