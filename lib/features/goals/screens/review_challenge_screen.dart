
import 'package:flutter/material.dart';
import '../../../core/models/goal.dart';
import '../../../app/routes.dart';

import '../models/challenge_draft.dart';
import 'package:provider/provider.dart';
import '../../../core/services/database_service.dart';

class ReviewChallengeScreen extends StatefulWidget {
  final ChallengeDraft draft;

  const ReviewChallengeScreen({
    super.key,
    required this.draft,
  });

  @override
  State<ReviewChallengeScreen> createState() =>
      _ReviewChallengeScreenState();
}

class _ReviewChallengeScreenState extends State<ReviewChallengeScreen> {
  bool _isCreating = false;

DateTime _calculateEndDate(DateTime startsAt) {
  switch (widget.draft.period) {
    case GoalPeriod.daily:
      return startsAt.add(const Duration(days: 1));
    case GoalPeriod.weekly:
      return startsAt.add(const Duration(days: 7));
  }
}


Future<void> _createChallenge() async {
  if (_isCreating) return;

  final startsAt = DateTime.now();
  final endsAt = _calculateEndDate(startsAt);

  final goal = Goal(
    id: '',
    title: widget.draft.title,
    type: widget.draft.type,
    metric: widget.draft.metric,
    period: widget.draft.period,
    targetValue: widget.draft.targetValue,
    startsAt: startsAt,
    endsAt: endsAt,
    participantIds: widget.draft.participantIds,
  );

  setState(() {
    _isCreating = true;
  });

    try {
  await context.read<DatabaseService>().createChallenge(
    goal: goal,
    taskIds: widget.draft.selectedTaskIds,
  );

  if (!mounted) return;

  Navigator.of(context).pushNamedAndRemoveUntil(
    AppRoutes.home,
    (route) => false,
  );
} catch (error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unable to create challenge: $error'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isCreating = false;
      });
    }
  }
}

  @override
Widget build(BuildContext context) {
  final database = context.watch<DatabaseService>();
  final selectedParticipants = widget.draft.participantIds
    .map((id) => database.userById(id))
    .where((user) => user != null)
    .toList();

  final selectedTasks = database.tasks
      .where((task) => widget.draft.selectedTaskIds.contains(task.id))
      .toList();

  return Scaffold(
      appBar: AppBar(
        title: const Text('Review Challenge'),
      ),
      bottomNavigationBar: SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: FilledButton(
  onPressed: _isCreating ? null : _createChallenge,
  child: _isCreating
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        )
      : const Text('Create Challenge'),
),
  ),
),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      widget.draft.title,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 16),
    Text(
  'Challenge Type: ${switch (widget.draft.type) {
    GoalType.individual => 'Individual',
    GoalType.family => 'Family',
    GoalType.team => 'Team',
  }}',
),
    const SizedBox(height: 12),
Text(
  'Goal Metric: ${switch (widget.draft.metric) {
    GoalMetric.tasksCompleted => 'Tasks Completed',
    GoalMetric.xpEarned => 'XP Earned',
    GoalMetric.coinsEarned => 'Coins Earned',
  }}',
),
const SizedBox(height: 12),
Text(
  'Target: ${widget.draft.targetValue}',
),
const SizedBox(height: 12),
Text(
  'Duration: ${switch (widget.draft.period) {
    GoalPeriod.daily => 'Daily',
    GoalPeriod.weekly => 'Weekly',
  }}',
),
const SizedBox(height: 12),
Text(
  'Participants: ${widget.draft.type.name == 'family' ? 'Entire Household' : '${widget.draft.participantIds.length} selected'}',
),
if (widget.draft.type != GoalType.family)
  for (final participant in selectedParticipants)
    Padding(
      padding: const EdgeInsets.only(left: 16, top: 8),
      child: Text(
        '• ${participant!.name}',
      ),
    ),
const SizedBox(height: 12),
Text(
  'Selected Tasks: ${widget.draft.selectedTaskIds.length}',
),
const SizedBox(height: 8),
if (selectedTasks.isEmpty)
  const Text('No existing tasks selected.')
else
  for (final task in selectedTasks)
    Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        '• ${task.title} (${task.rewardXp} XP, ${task.coinReward} Coins)',
      ),
    ),
  ],
),
      ),
    );
  }
}
