import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../task_completion_flow.dart';
import '../widgets/task_proof_card.dart';

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
    final isParent = context.watch<AuthService>().currentUser?.isParent ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.15),
                          child: Icon(
                            TaskIconCatalog.resolve(task.icon).icon,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
                        ),
                      ],
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(task.description, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 24),
                        const SizedBox(width: 2),
                        Text('Reward: +${task.rewardXp} XP', style: Theme.of(context).textTheme.bodyMedium),
                        if (task.coinReward > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 22),
                          const SizedBox(width: 2),
                          Text('+${task.coinReward} coins', style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ],
                    ),
                    if (task.requiresPhoto) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.photo_camera_outlined, size: 18, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Photo proof required',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isParent && task.proof != null && task.status != TaskStatus.pending) ...[
                const SizedBox(height: 16),
                TaskProofCard(proof: task.proof!),
              ],
              const SizedBox(height: 22),
              if (isParent && task.status == TaskStatus.pending) ...[
                // Pool tasks have no child to reward, so they're only editable.
                if (!task.isAvailable) ...[
                  AppButton(
                    label: 'Mark as Complete',
                    icon: Icons.check_circle_outline,
                    variant: AppButtonVariant.success,
                    onPressed: () => _parentComplete(context, resolvedTask),
                  ),
                  const SizedBox(height: 8),
                ],
                AppButton(
                  label: 'Edit Task',
                  icon: Icons.edit_outlined,
                  variant: task.isAvailable ? AppButtonVariant.primary : AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.taskEdit, arguments: resolvedTask.id),
                ),
              ]
              else if (!isParent && task.status == TaskStatus.completed)
                const Center(child: Text('⏳ Waiting for a parent to approve'))
              else if (task.status == TaskStatus.pending)
                AppButton(
                  label: task.requiresPhoto ? 'Take Photo to Finish' : 'Mark as Complete',
                  variant: AppButtonVariant.success,
                  icon: task.requiresPhoto ? Icons.photo_camera : Icons.check_circle_outline,
                  onPressed: () => startTaskCompletion(context, resolvedTask, celebrate: true),
                )
              else if (task.status == TaskStatus.completed) ...[
                AppButton(
                  label: task.proofNeedsReview ? 'Approve Anyway' : 'Approve Task',
                  icon: Icons.check_circle_outline,
                  variant: AppButtonVariant.success,
                  onPressed: () async {
                    await context.read<DatabaseService>().approveTask(resolvedTask.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Send Back to Redo',
                  icon: Icons.undo,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _confirmSendBack(context, resolvedTask),
                ),
              ] else
                const Center(child: Text('✅ Completed & approved')),
            ],
          ),
        ),
      ),
    );
  }

  /// A parent finishing a task themselves needs no separate approval: it's
  /// approved and rewarded in one step (photo proof is skipped too).
  Future<void> _parentComplete(BuildContext context, TaskModel task) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await context.read<DatabaseService>().parentCompleteTask(task.id);
    messenger.showSnackBar(SnackBar(content: Text('"${task.title}" completed - rewards granted!')));
    if (navigator.mounted) navigator.pop();
  }

  Future<void> _confirmSendBack(BuildContext context, TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send Back?'),
        content: Text(
          '"${task.title}" goes back to the to-do list'
          '${task.proof != null ? ' and the photo is deleted' : ''}. No rewards are given.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Send Back')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<DatabaseService>().uncompleteTask(task.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${task.title}" sent back to redo.')));
    Navigator.of(context).pop();
  }
}
