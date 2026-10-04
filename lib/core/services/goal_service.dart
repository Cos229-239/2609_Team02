import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goal.dart';
import '../models/goal_contribution.dart';

/// Handles persistence and progress tracking for household goals.
class GoalService {
  GoalService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Records a qualifying contribution toward a household goal.
  ///
  /// Returns true when the contribution is recorded and progress changes.
  /// Returns false when the contribution cannot be applied.
  Future<bool> recordContribution({
    required String householdId,
    required String goalId,
    required GoalContribution contribution,
  }) async {
    final householdRef = _firestore.collection('households').doc(householdId);

    final goalRef = householdRef.collection('goals').doc(goalId);

    final contributionRef = goalRef
        .collection('contributions')
        .doc(contribution.activityId);

    return _firestore.runTransaction<bool>((transaction) async {
      // Firestore transactions require reads before writes.
      final goalSnapshot = await transaction.get(goalRef);

      if (!goalSnapshot.exists) return false;

      final goal = Goal.fromFirestore(goalSnapshot);

      DocumentSnapshot<Map<String, dynamic>>? householdSnapshot;

      if (goal.type == GoalType.family) {
        householdSnapshot = await transaction.get(householdRef);
      }

      // Only activity recorded during the goal's active period may count.
      if (!goal.isActiveAt(contribution.recordedAt)) return false;

      // Individual and team goals use explicit participant lists.
      if (goal.type == GoalType.family) {
        if (householdSnapshot == null || !householdSnapshot.exists) {
          return false;
        }

        final memberIds = List<String>.from(
          householdSnapshot.data()?['memberIds'] as List? ?? const [],
        );

        if (!memberIds.contains(contribution.userId)) {
          return false;
        }
      } else if (!goal.participantIds.contains(contribution.userId)) {
        return false;
      }

      final contributionSnapshot = await transaction.get(contributionRef);

      // The same source activity may only contribute once to this goal.
      if (contributionSnapshot.exists) return false;

      final calculatedProgress = goal.currentProgress + contribution.amount;

      final newProgress = calculatedProgress > goal.targetValue
          ? goal.targetValue
          : calculatedProgress;

      final reachedTarget = newProgress >= goal.targetValue;

      transaction.set(contributionRef, contribution.toFirestore());

      transaction.update(goalRef, {
        'currentProgress': newProgress,
        if (reachedTarget)
          'completedAt': Timestamp.fromDate(contribution.recordedAt),
      });

      return true;
    });
  }
}
