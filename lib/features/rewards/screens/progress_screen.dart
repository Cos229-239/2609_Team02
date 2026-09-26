import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/user.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

/// "Progress" tab — the parent's overview of the whole household: each
/// child's XP progress, plus every task in the household broken out into
/// Overdue, Pending and Completed so a parent can see at a glance what
/// still needs attention without hunting through each child's task list.
///
/// This only returns the tab's content; `MainTabShell` supplies the
/// shared app bar, bottom nav bar and `SafeArea`.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final children = db.children;

    final overdue = <TaskModel>[];
    final pending = <TaskModel>[];
    final awaitingApproval = <TaskModel>[];
    final completed = <TaskModel>[];
    for (final task in db.tasks) {
  if (task.status == TaskStatus.approved) {
    completed.add(task);
  } else if (task.status == TaskStatus.completed) {
    awaitingApproval.add(task);
  } else if (_isOverdue(task.dueDate)) {
    overdue.add(task);
  } else {
    pending.add(task);
  }
}
    // Soonest-due first within each group; tasks with no due date sort last.
    int byDueDate(TaskModel a, TaskModel b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    }

    overdue.sort(byDueDate);
    pending.sort(byDueDate);
    awaitingApproval.sort(byDueDate);
    completed.sort((a, b) => byDueDate(b, a));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
children: [
  Text(
    'Family Progress',
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w700,
    ),
  ),
  const SizedBox(height: 6),
  Text(
    'See how everyone is doing this week.',
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.grey.shade600,
      fontSize: 14,
    ),
  ),
  const SizedBox(height: 20),
        for (final child in children) ...[
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(child.avatarEmoji, style: const TextStyle(fontSize: AppConstants.emojiIconMd)),
                    const SizedBox(width: 8),
                    Text(child.name, style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text('+${child.xp} XP'),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: LinearProgressIndicator(
                    value: (child.xp / AppConstants.levelUpXpThreshold).clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    color: AppColors.growthGreen,
                    backgroundColor: const Color.fromARGB(255, 223, 244, 199),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${AppConstants.levelUpXpThreshold - child.xp > 0 ? AppConstants.levelUpXpThreshold - child.xp : 0} XP to next level',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Text('All Tasks:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        )),
        const SizedBox(height: 4),
        Text(
          'Every task in the household, at a glance.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _TaskSection(
          icon: Icons.error_outline,
          title: 'Overdue',
          color: Colors.red.shade600,
          tasks: overdue,
          db: db,
          emptyLabel: 'Nothing overdue — nice work!',
        ),
        const SizedBox(height: 12),
        _TaskSection(
          icon: Icons.schedule,
          title: 'Pending',
          color: AppColors.primaryBlue,
          tasks: pending,
          db: db,
          emptyLabel: 'No pending tasks right now.',
        ),

        const SizedBox(height: 12),
        _TaskSection(
        icon: Icons.hourglass_bottom,
        title: 'Awaiting Approval',
        color: Colors.orange,
        tasks: awaitingApproval,
        db: db,
        emptyLabel: 'No tasks waiting for approval.',
),
        const SizedBox(height: 12),
        _TaskSection(
          icon: Icons.check_circle_outline,
          title: 'Completed',
          color: AppColors.growthGreen,
          tasks: completed,
          db: db,
          emptyLabel: 'Nothing completed yet.',
        ),
      ],
    );
  }

  static bool _isOverdue(DateTime? dueDate) {
    if (dueDate == null) return false;
    final today = DateTime.now();
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return dueDay.isBefore(todayDay);
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.tasks,
    required this.db,
    required this.emptyLabel,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<TaskModel> tasks;
  final DatabaseService db;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: color, child: Icon(icon, size: 14, color: Colors.white)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                child: Text('${tasks.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),

          for (final task in tasks) ...[
            const SizedBox(height: 8),
            _TaskProgressRow(task: task, assignee: _assigneeFor(task)),
          ],
      ],
    );
  }

  AppUser? _assigneeFor(TaskModel task) {
    if (task.assignedToUserId == null) return null;
    return db.userById(task.assignedToUserId!);
  }
}

class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({required this.task, required this.assignee});

  final TaskModel task;
  final AppUser? assignee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ), 
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.15),
            child: Icon(TaskIconCatalog.resolve(task.icon).icon, color: theme.colorScheme.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
                Text(
                  '${assignee?.name ?? 'Household'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
                  fontSize: 13),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Transform.translate(
                offset: const Offset(8, 0),
                child: _StatusPill(task: task),
              ),
              
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text('+${task.rewardXp} XP', style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                  )),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dueLabel(DateTime? dueDate) {
    if (dueDate == null) return 'No due date';
    final today = DateTime.now();
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final difference = dueDay.difference(todayDay).inDays;
    if (difference < 0) return difference == -1 ? 'Overdue by 1 day' : 'Overdue by ${-difference} days';
    if (difference == 0) return 'Due Today';
    if (difference == 1) return 'Due Tomorrow';
    return 'Due in $difference Days';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.task});

  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (task.status) {
      TaskStatus.pending => ('To Do', Colors.grey, Icons.radio_button_unchecked),
      TaskStatus.completed => ('Awaiting Approval', Colors.orange, Icons.hourglass_bottom),
      TaskStatus.approved => ('Approved', AppColors.growthGreen, Icons.check_circle),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: AppConstants.captionFontSize)),
        ],
      ),
    );
  }
}
