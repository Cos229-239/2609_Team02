import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

/// "Home" tab for a signed-in child. Unlike [HouseholdHomeScreen] (the
/// parent's dashboard with "Create Task" and the family roster), this is
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
    final nextRewardXp = nextTask?.rewardXp ?? 50;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Text('${_greeting()}, ${child.name}! 👋', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
           "You're doing great!" " " "Keep going!",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _NextRewardCard(
          progress: progress,
          nextRewardXp: nextRewardXp,
          completedCount: completedCount,
          totalCount: totalCount,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text("Today's Tasks", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            _CountBadge(completed: completedCount, total: totalCount),
          ],
        ),
        const SizedBox(height: 4),
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
          const SizedBox(height: 8),

AppCard(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  child: Row(
    children: [
      const Icon(
        Icons.emoji_events_rounded,
        color: Colors.amber,
        size: 34,
      ),
      const SizedBox(width: 8),

      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keep it up, ${child.name}!',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              remaining == 1
                  ? "You're only 1 task away from your next reward!"
                  : "Keep completing tasks to earn your next reward!",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              )
            ),
          ],
        ),
      ),

      const SizedBox(width: 8),

      Text(
        '+$nextRewardXp XP',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    ],
  ),
),
        if (remaining > 0) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.growthGreen.withValues(alpha: 0.08),
            child: Row(
              children: [
                const Text('🦖', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Keep it up, ${child.name}!', style: Theme.of(context).textTheme.titleMedium),
                      Text(
  "1 task away from your next reward!",
  style: Theme.of(context).textTheme.bodySmall,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
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
      color:Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
  scale: 1.35,
  child: Transform.rotate(
    angle: 0.8,
    child: CircularProgressIndicator(
    value: 0.90,
    strokeWidth: 4,
    backgroundColor: Colors.transparent,
    valueColor: const AlwaysStoppedAnimation<Color>(
    Colors.amber,
    ),
  ),
),
                ),
Positioned(
  top: -2,
  left: 40,
  child: Container(
  width: 22,
  height: 38,
  decoration: BoxDecoration(
    color: Colors.amber,
    shape: BoxShape.circle,
  ),
  child: const Icon(
    Icons.star,
    size: 20,
    color: Colors.white,
  ),
),
),
  Stack(
    alignment: Alignment.center,
  children: [
    Positioned(
  top: -2,
  left: 25,
  child: const Icon(
    Icons.star,
    size: 18,
    color: AppColors.growthGreen,
  ),
),
    
    
    Text(
      '${(progress * 100).round()}%',
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 10,
      ),
    ),
  ],
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
                      ?.copyWith(color: Colors.black, fontWeight: FontWeight.w600),
                ),
                Text(
  '+$nextRewardXp XP',
  style: Theme.of(context).textTheme.titleLarge,
),
                const SizedBox(height: 8),

ClipRRect(
  borderRadius: BorderRadius.circular(10),
  child: LinearProgressIndicator(
    value: totalCount == 0 ? 0 : completedCount / totalCount,
    minHeight: 8,
    backgroundColor: Colors.grey.shade300,
    valueColor: const AlwaysStoppedAnimation<Color>(
      Color(0xFF4CAF50),
    ),
  ),
),

const SizedBox(height: 4),
                
                Text(
                  '$completedCount of $totalCount tasks completed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
     
    ),
    const SizedBox(height: 6),
    
  ],
),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.growthGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: AppColors.growthGreen),
          const SizedBox(width: 4),
Text(
  '$completed of $total',
  style: const TextStyle(
    color: AppColors.growthGreen,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  ),
),        ],
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
  radius: 18,
  backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
  child: Icon(
    task.title == 'Go outside'
        ? Icons.wb_sunny_outlined
        : task.title == 'Eat Sushi'
            ? Icons.restaurant_outlined
            : TaskIconCatalog.resolve(task.icon).icon,
    color: AppColors.growthGreen,
    size: 18,
  ),
),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600)),
                Text(
                  '${task.isRecurring ? 'Daily Task' : 'One-time Task'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (task.isCompleted)
  Column(
  crossAxisAlignment: CrossAxisAlignment.end,
  children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.growthGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '✓ Completed',
        style: TextStyle(
          color: AppColors.growthGreen,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    const SizedBox(height: 4),
    const Text(
      '★ +50 XP',
      style: TextStyle(
        color: Colors.amber,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  ],
)
          else
  InkWell(
    onTap: onComplete,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.shade400,
          width: 2,
        ),
      ),
    ),
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
