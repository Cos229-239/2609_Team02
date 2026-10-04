import 'package:cloud_firestore/cloud_firestore.dart';

/// Defines who contributes toward a goal.
enum GoalType { individual, family, team }

/// Famotive activity measured by a goal.
enum GoalMetric { tasksCompleted, xpEarned, coinsEarned }

/// Supported duration for a goal.
enum GoalPeriod { daily, weekly }

/// A cooperative or individual activity goal within a household.
///
/// Household ownership is established by the Firestore path:
/// `households/{householdId}/goals/{goalId}`.
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.type,
    required this.metric,
    required this.period,
    required this.targetValue,
    required this.startsAt,
    required this.endsAt,
    this.currentProgress = 0,
    this.participantIds = const [],
    this.completedAt,
  });

  final String id;
  final String title;

  /// Determines whether this is an individual, family, or team goal.
  final GoalType type;

  /// Activity measured toward [targetValue].
  final GoalMetric metric;

  /// Daily or weekly goal period.
  final GoalPeriod period;

  /// Amount required to complete the goal.
  final int targetValue;

  /// Aggregate progress from qualifying contributions.
  final int currentProgress;

  /// Explicit participants for individual and team goals.
  ///
  /// Family goals may leave this empty and use household membership.
  final List<String> participantIds;

  /// Beginning of the period in which activity may contribute.
  final DateTime startsAt;

  /// End of the period in which activity may contribute.
  final DateTime endsAt;

  /// Time at which the goal reached its target; null while incomplete.
  final DateTime? completedAt;

  /// Whether this goal has reached its completion target.
  bool get isCompleted => completedAt != null;

  /// Whether [time] falls within this goal's active period.
  ///
  /// Completed goals are no longer active even if their original period
  /// has not ended.
  bool isActiveAt(DateTime time) {
    if (isCompleted) return false;

    return !time.isBefore(startsAt) && time.isBefore(endsAt);
  }

  factory Goal.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};

    return Goal(
      id: doc.id,
      title: data['title'] as String? ?? '',
      type: GoalType.values.firstWhere(
        (type) => type.name == data['type'],
        orElse: () => GoalType.individual,
      ),
      metric: GoalMetric.values.firstWhere(
        (metric) => metric.name == data['metric'],
        orElse: () => GoalMetric.tasksCompleted,
      ),
      period: GoalPeriod.values.firstWhere(
        (period) => period.name == data['period'],
        orElse: () => GoalPeriod.weekly,
      ),
      targetValue: data['targetValue'] as int? ?? 0,
      currentProgress: data['currentProgress'] as int? ?? 0,
      participantIds:
          List<String>.from(data['participantIds'] as List? ?? const []),
      startsAt:
          (data['startsAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endsAt:
          (data['endsAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'type': type.name,
      'metric': metric.name,
      'period': period.name,
      'targetValue': targetValue,
      'currentProgress': currentProgress,
      'participantIds': participantIds,
      'startsAt': Timestamp.fromDate(startsAt),
      'endsAt': Timestamp.fromDate(endsAt),
      'completedAt':
          completedAt == null ? null : Timestamp.fromDate(completedAt!),
    };
  }
}