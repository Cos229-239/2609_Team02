import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

/// "Home" tab for a signed-in child. Unlike [HouseholdHomeScreen] (the
/// parent's dashboard with "Assign Tasks" and the family roster), this is
/// the kid-facing view from the mid-fi mockups: today's progress toward
/// the next reward, plus a simple checklist of today's tasks a child can
/// mark complete themselves. Children can't create, edit or assign tasks
/// from here — that stays parent-only.
///
/// This only returns the tab's content; [MainTabShell] supplies the
/// shared app bar, bottom nav bar and [SafeArea].
class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final child = auth.currentUser;

    if (child == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final tasks = db.tasksForUser(child.id);
    final completedCount = tasks.where((t) => t.isCompleted).length;
    final totalCount = tasks.length;
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final remaining = totalCount - completedCount;
    TaskModel? nextTask;
    for (final task in tasks) {
      if (!task.isCompleted) {
        nextTask = task;
        break;
      }
    }
    final nextRewardXp = nextTask?.rewardXp ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${_greeting()}, ${child.name}! 👋', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          remaining == 0 ? "You're all done for today!" : "You're doing great! Keep going!",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        _NextRewardCard(
          progress: progress,
          nextRewardXp: nextRewardXp,
          completedCount: completedCount,
          totalCount: totalCount,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text("Today's Tasks", style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            _CountBadge(completed: completedCount, total: totalCount),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No tasks assigned yet — check Tasks to claim one!'),
          )
        else
          for (final task in tasks) ...[
            _ChildTaskRow(
              task: task,
              onComplete: () => context.read<DatabaseService>().completeTask(task.id),
            ),
            const SizedBox(height: 8),
          ],
        if (remaining > 0) ...[
          const SizedBox(height: 12),
          AppCard(
            color: AppColors.growthGreen.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Text('🦖', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Keep it up, ${child.name}!', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        remaining == 1
                            ? "You're only 1 task away from your next reward!"
                            : "You're only $remaining tasks away from your next reward!",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _NextRewardCard extends StatelessWidget {
  const _NextRewardCard({
    required this.progress,
    required this.nextRewardXp,
    required this.completedCount,
    required this.totalCount,
  });

  final double progress;
  final int nextRewardXp;
  final int completedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.growthGreen.withValues(alpha: 0.08),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 5,
                  backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.growthGreen),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next Reward',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.growthGreen, fontWeight: FontWeight.w600),
                ),
                Text('+$nextRewardXp XP', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '$completedCount of $totalCount tasks completed',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Icon(Icons.stars_rounded, color: Colors.amber, size: 36),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.growthGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: AppColors.growthGreen),
          const SizedBox(width: 4),
          Text('$completed of $total', style: const TextStyle(color: AppColors.growthGreen, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChildTaskRow extends StatelessWidget {
  const _ChildTaskRow({required this.task, required this.onComplete});

  final TaskModel task;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      color: task.isCompleted ? AppColors.growthGreen.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.15),
            child: Text(task.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleMedium),
                Text(
                  '${task.isRecurring ? 'Daily Task' : 'One-time Task'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (task.isCompleted)
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.growthGreen,
              child: Icon(Icons.check, color: Colors.white, size: 16),
            )
          else
            ElevatedButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Complete'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
            ),
        ],
      ),
    );
  }

  String _dueLabel(DateTime? dueDate) {
    if (dueDate == null) return 'Due Today';
    final today = DateTime.now();
    final difference = DateTime(dueDate.year, dueDate.month, dueDate.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (difference <= 0) return 'Due Today';
    if (difference == 1) return 'Due Tomorrow';
    return 'Due in $difference Days';
  }
}
