import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/goal.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final db = context.watch<DatabaseService>();
    final now = DateTime.now();

    final visibleGoals = db.goals.where((goal) {
      if (user == null) return false;
      if (user.isParent) return true;

      return goal.type == GoalType.family ||
          goal.participantIds.contains(user.id);
    }).toList();

    final active = visibleGoals.where((goal) => goal.isActiveAt(now)).toList();

    final completed = visibleGoals.where((goal) => goal.isCompleted).toList();

    final scheduled = visibleGoals
        .where((goal) => !goal.isCompleted && now.isBefore(goal.startsAt))
        .toList();

    final expired = visibleGoals
        .where((goal) => !goal.isCompleted && !now.isBefore(goal.endsAt))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Family Challenges & Goals')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          Text(
            'Active Challenges',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),

          if (active.isEmpty) const Text('No active challenges right now.'),

          for (final goal in active) ...[
            _GoalCard(goal: goal),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 24),

          Text(
            'Completed Challenges',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),

          if (completed.isEmpty) const Text('No completed challenges yet.'),

          for (final goal in completed) ...[
            _GoalCard(goal: goal),
            const SizedBox(height: 12),
          ],
          if (scheduled.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Scheduled Challenges',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final goal in scheduled) ...[
              _GoalCard(goal: goal),
              const SizedBox(height: 12),
            ],
          ],
          if (expired.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Past Challenges',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final goal in expired) ...[
              _GoalCard(goal: goal),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
      floatingActionButton: user?.isParent == true
          ? FloatingActionButton.extended(
              onPressed: null,
              icon: const Icon(Icons.add),
              label: const Text('Create Challenge'),
            )
          : null,
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final progress = goal.targetValue > 0
        ? (goal.currentProgress / goal.targetValue).clamp(0.0, 1.0).toDouble()
        : 0.0;

    final metricLabel = switch (goal.metric) {
      GoalMetric.tasksCompleted => 'tasks',
      GoalMetric.xpEarned => 'XP',
      GoalMetric.coinsEarned => 'coins',
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(goal.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text('${goal.currentProgress} / ${goal.targetValue} $metricLabel'),
        ],
      ),
    );
  }
}
