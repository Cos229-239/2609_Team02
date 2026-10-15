import '../../../core/models/goal.dart';


class ChallengeDraft {
  final String title;
  final GoalType type;
  final GoalMetric metric;
  final int targetValue;
  final GoalPeriod period;
  final List<String> participantIds;
  final List<String> selectedTaskIds;

  const ChallengeDraft({
    required this.title,
    required this.type,
    required this.metric,
    required this.targetValue,
    required this.period,
    required this.participantIds,
    this.selectedTaskIds = const [],
  });
}
