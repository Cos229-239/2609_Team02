import '../../../core/models/goal.dart';
import '../../../core/models/task.dart';

class ChallengeDraft {
  final String title;
  final GoalType type;
  final GoalMetric metric;
  final int targetValue;
  final GoalPeriod period;
  final List<String> participantIds;
  final List<String> selectedTaskIds;

  // New chores remain unsaved until the parent creates the challenge.
  final List<TaskModel> newTasks;

  const ChallengeDraft({
    required this.title,
    required this.type,
    required this.metric,
    required this.targetValue,
    required this.period,
    required this.participantIds,
    this.selectedTaskIds = const [],
    this.newTasks = const [],
  });
}
