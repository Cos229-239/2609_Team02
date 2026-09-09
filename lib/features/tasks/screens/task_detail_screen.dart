import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

/// Detail view for a single task, with the primary "mark complete" action
/// that drives the sample flow into the celebration screen.
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    TaskModel? task;
    for (final t in db.tasks) {
      if (t.id == taskId) {
        task = t;
        break;
      }
    }

    if (task == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Task not found.')));
    }
    final resolvedTask = task;

    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(task.icon, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
                        ),
                      ],
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(task.description, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text('Reward: ${task.rewardXp} XP', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (task.status == TaskStatus.pending)
                AppButton(
                  label: 'Mark as Complete',
                  variant: AppButtonVariant.success,
                  icon: Icons.check_circle_outline,
                  onPressed: () {
                    context.read<DatabaseService>().completeTask(resolvedTask.id);
                    Navigator.of(context)
                        .pushReplacementNamed(AppRoutes.taskCompletion, arguments: resolvedTask.id);
                  },
                )
              else if (task.status == TaskStatus.completed)
                AppButton(
                  label: 'Approve Task',
                  onPressed: () {
                    context.read<DatabaseService>().approveTask(resolvedTask.id);
                    Navigator.of(context).pop();
                  },
                )
              else
                const Center(child: Text('✅ Completed & approved')),
            ],
          ),
        ),
      ),
    );
  }
}
