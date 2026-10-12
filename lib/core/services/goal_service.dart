import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/goal.dart';
import '../models/goal_contribution.dart';

/// A validated contribution ready to be written in a Firestore transaction.
class PreparedGoalContribution {
  const PreparedGoalContribution({
    required this.goalRef,
    required this.contributionRef,
    required this.contribution,
    required this.newProgress,
    required this.reachedTarget,
  });

  final DocumentReference<Map<String, dynamic>> goalRef;
  final DocumentReference<Map<String, dynamic>> contributionRef;
  final GoalContribution contribution;
  final int newProgress;
  final bool reachedTarget;

  /// Writes the contribution and updated goal progress.
  ///
  /// Call only after all required transaction reads are complete.
  void apply(Transaction transaction) {
    transaction.set(contributionRef, contribution.toFirestore());

    transaction.update(goalRef, {
      'currentProgress': newProgress,
      if (reachedTarget)
        'completedAt': Timestamp.fromDate(contribution.recordedAt),
    });
  }
}

/// Handles persistence and progress tracking for household goals.
class GoalService {
  GoalService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Validates and prepares a contribution without writing anything.
  ///
  /// This allows other services to include goal progress in their
  /// existing Firestore transactions.
  Future<PreparedGoalContribution?> prepareContribution({
    required Transaction transaction,
    required String householdId,
    required String goalId,
    required GoalContribution contribution,
    DocumentSnapshot<Map<String, dynamic>>? existingGoalSnapshot,
  }) async {
    final householdRef = _firestore.collection('households').doc(householdId);
    final goalRef = householdRef.collection('goals').doc(goalId);
    final contributionRef = goalRef
        .collection('contributions')
        .doc(contribution.activityId);

    final goalSnapshot = existingGoalSnapshot ?? await transaction.get(goalRef);

    if (!goalSnapshot.exists) return null;

    final goal = Goal.fromFirestore(goalSnapshot);

    DocumentSnapshot<Map<String, dynamic>>? householdSnapshot;

    if (goal.type == GoalType.family) {
      householdSnapshot = await transaction.get(householdRef);
    }

    if (!goal.isActiveAt(contribution.recordedAt)) return null;

    if (goal.type == GoalType.family) {
      if (householdSnapshot == null || !householdSnapshot.exists) {
        return null;
      }

      final memberIds = List<String>.from(
        householdSnapshot.data()?['memberIds'] as List? ?? const [],
      );

      if (!memberIds.contains(contribution.userId)) return null;
    } else if (!goal.participantIds.contains(contribution.userId)) {
      return null;
    }

    final contributionSnapshot = await transaction.get(contributionRef);

    if (contributionSnapshot.exists) return null;

    final calculatedProgress = goal.currentProgress + contribution.amount;

    final newProgress = calculatedProgress > goal.targetValue
        ? goal.targetValue
        : calculatedProgress;

    return PreparedGoalContribution(
      goalRef: goalRef,
      contributionRef: contributionRef,
      contribution: contribution,
      newProgress: newProgress,
      reachedTarget: newProgress >= goal.targetValue,
    );
  }

  /// Records a qualifying contribution toward a household goal.
  /// Returns true when the contribution is recorded and progress changes.
  /// Returns false when the contribution cannot be applied.
  Future<bool> recordContribution({
    required String householdId,
    required String goalId,
    required GoalContribution contribution,
  }) async {
    return _firestore.runTransaction<bool>((transaction) async {
      final prepared = await prepareContribution(
        transaction: transaction,
        householdId: householdId,
        goalId: goalId,
        contribution: contribution,
      );

      if (prepared == null) return false;

      prepared.apply(transaction);
      return true;
    });
  }
}
