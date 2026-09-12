import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

/// "Completion of children tasks" — the celebration screen shown right
/// after a task is marked done, recapping what was completed and what
/// was earned. Ends the sample flow by returning to the child's task
/// list / home.
class TaskCompletionScreen extends StatelessWidget {
  const TaskCompletionScreen({super.key, required this.taskId});

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
    final child = task == null ? null : db.userById(task.assignedToUserId);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                'Congratulations${child != null ? ', ${child.name}' : ''}!',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'You completed your task and earned amazing rewards!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (task != null)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text('Task Completed', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${task.icon}  ${task.title}'),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text('Reward Earned', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('+${task.rewardXp} XP'),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              AppButton(
                label: 'Great Job! Keep Up the Fantastic Work!',
                variant: AppButtonVariant.success,
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
