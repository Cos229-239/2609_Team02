import 'package:cloud_firestore/cloud_firestore.dart';

/// Famotive activity that can contribute progress toward a goal.
enum GoalActivityType { taskApproval }

/// A single qualifying activity contribution toward a goal.
///
/// Contributions are stored beneath a specific goal:
/// `households/{householdId}/goals/{goalId}/contributions/{activityId}`.
///
/// The Firestore document ID is the source [activityId], which allows the
/// goal service to prevent the same activity from contributing more than
/// once toward the same goal.
class GoalContribution {
  const GoalContribution({
    required this.activityId,
    required this.userId,
    required this.amount,
    required this.activityType,
    required this.recordedAt,
  });

  /// ID of the source activity that generated this contribution.
  ///
  /// For task approvals, this is the task occurrence ID.
  final String activityId;

  /// User whose activity produced this contribution.
  final String userId;

  /// Progress added toward the goal.
  ///
  /// Examples:
  /// - tasksCompleted: 1
  /// - xpEarned: the task's XP reward
  /// - coinsEarned: the task's coin reward
  final int amount;

  /// Type of Famotive activity that produced this contribution.
  final GoalActivityType activityType;

  /// Time the qualifying activity was recorded.
  final DateTime recordedAt;

  factory GoalContribution.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};

    return GoalContribution(
      activityId: doc.id,
      userId: data['userId'] as String? ?? '',
      amount: data['amount'] as int? ?? 0,
      activityType: GoalActivityType.values.firstWhere(
        (type) => type.name == data['activityType'],
        orElse: () => GoalActivityType.taskApproval,
      ),
      recordedAt:
          (data['recordedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'amount': amount,
      'activityType': activityType.name,
      'recordedAt': Timestamp.fromDate(recordedAt),
    };
  }
}