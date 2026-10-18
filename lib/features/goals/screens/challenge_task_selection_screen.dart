
import 'package:flutter/material.dart';
import 'review_challenge_screen.dart';
import 'package:provider/provider.dart';

import '../../../core/models/goal.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../models/challenge_draft.dart';

class ChallengeTaskSelectionScreen extends StatefulWidget {
  final ChallengeDraft draft;

  const ChallengeTaskSelectionScreen({
    super.key,
    required this.draft,
  });

  @override
  State<ChallengeTaskSelectionScreen> createState() =>
      _ChallengeTaskSelectionScreenState();
}

class _ChallengeTaskSelectionScreenState
    extends State<ChallengeTaskSelectionScreen> {
  late final Set<String> _selectedTaskIds =
      widget.draft.selectedTaskIds.toSet();

  int _calculateSuggestedTarget(List<TaskModel> selectedTasks) {
  switch (widget.draft.metric) {
    case GoalMetric.tasksCompleted:
      return selectedTasks.length;

    case GoalMetric.xpEarned:
      return selectedTasks.fold<int>(
        0,
        (total, task) => total + task.rewardXp,
      );

    case GoalMetric.coinsEarned:
      return selectedTasks.fold<int>(
        0,
        (total, task) => total + task.coinReward,
      );
  }
}

  ChallengeDraft _buildUpdatedDraft() {
  final database = context.read<DatabaseService>();

  final selectedTasks = database.tasks
      .where((task) => _selectedTaskIds.contains(task.id))
      .toList();

  final suggestedTarget = _calculateSuggestedTarget(selectedTasks);

  return ChallengeDraft(
    title: widget.draft.title,
    type: widget.draft.type,
    metric: widget.draft.metric,
    targetValue: suggestedTarget,
    period: widget.draft.period,
    participantIds: widget.draft.participantIds,
    selectedTaskIds: _selectedTaskIds.toList(),
  );
}

  bool _isEligibleTask(TaskModel task) {
    return task.status == TaskStatus.pending &&
        task.goalId == null &&
        !task.isArchived &&
        !task.isUpcoming &&
        !task.isRecurring &&
        (widget.draft.type == GoalType.family ||
            task.assignedToUserId == null ||
            widget.draft.participantIds.contains(task.assignedToUserId));
  }

  @override
  Widget build(BuildContext context) {
    final database = context.watch<DatabaseService>();

    final eligibleTasks = database.activeTasks
        .where(_isEligibleTask)
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return Scaffold(
      bottomNavigationBar: SafeArea(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: FilledButton(
      onPressed: () {
  if (_selectedTaskIds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select at least one task to continue.'),
      ),
    );
    return;
  }

  final updatedDraft = _buildUpdatedDraft();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReviewChallengeScreen(
        draft: updatedDraft,
      ),
    ),
  );
},
      child: const Text('Next'),
    ),
  ),
),
      appBar: AppBar(
        title: const Text('Select Challenge Tasks'),
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
            const SizedBox(height: 12),
            const Text(
              'Choose existing tasks or create new tasks for this challenge.',
            ),
            const SizedBox(height: 24),
            Text(
              'Existing Tasks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (eligibleTasks.isEmpty)
              const Text('No eligible tasks are available.')
            else
              for (final task in eligibleTasks)
                CheckboxListTile(
                  title: Text(task.title),
                  subtitle: Text(
                    '${task.rewardXp} XP  •  ${task.coinReward} Coins',
                  ),
                  value: _selectedTaskIds.contains(task.id),
                  onChanged: (selected) {
                    setState(() {
                      if (selected == true) {
                        _selectedTaskIds.add(task.id);
                      } else {
                        _selectedTaskIds.remove(task.id);
                      }
                    });
                  },
                ),
          ],
        ),
      ),
    );
    
  }
}
