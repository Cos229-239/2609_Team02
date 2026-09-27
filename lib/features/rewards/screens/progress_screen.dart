import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/user.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_card.dart';

/// Distinct from `null` (dialog dismissed without a choice).
const String _householdPoolSentinel = '__household_pool__';

/// What a task row's trailing action does, based on its section.
enum _RowActions { edit, approveOrReassign, duplicateOnly }

/// "Progress" tab: each child's XP, and every task grouped into
/// Overdue, Pending, Awaiting Approval, Completed and Archived.
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
    for (final task in db.activeTasks) {
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
    final archived = db.archivedTasks;

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
    archived.sort((a, b) => byDueDate(b, a));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
children: [
  Text(
    'Family Progress',
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  ),
  const SizedBox(height: 6),
  Text(
    'See how everyone is doing this week.',
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.grey.shade600,
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
                    const SizedBox(width: 10),
                    Icon(Icons.monetization_on, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 2),
                    Text('${child.coins}'),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  child: LinearProgressIndicator(
                    value: (child.xp / AppConstants.levelUpXpThreshold).clamp(0.0, 1.0).toDouble(),
                    minHeight: 6,
                    color: AppColors.growthGreen,
                    backgroundColor: const Color.fromARGB(255, 223, 244, 199),
                  ),
                ),
                const SizedBox(height: 4),
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
        Text('All Tasks:', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Overdue/Pending tasks can be edited. Tasks already awaiting '
          'approval, completed or archived get quick actions instead.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _TaskSection(
          icon: Icons.error_outline,
          title: 'Overdue',
          color: Colors.red.shade600,
          tasks: overdue,
          db: db,
          emptyLabel: 'Nothing overdue - nice work!',
          actions: _RowActions.edit,
        ),
        const SizedBox(height: 4),
        _TaskSection(
          icon: Icons.schedule,
          title: 'Pending',
          color: AppColors.primaryBlue,
          tasks: pending,
          db: db,
          emptyLabel: 'No pending tasks right now.',
          actions: _RowActions.edit,
        ),

        const SizedBox(height: 20),
        _TaskSection(
        icon: Icons.hourglass_bottom,
        title: 'Awaiting Approval',
        color: Colors.orange,
        tasks: awaitingApproval,
        db: db,
        emptyLabel: 'No tasks waiting for approval.',
        actions: _RowActions.approveOrReassign,
),
        const SizedBox(height: 20),
        _TaskSection(
          icon: Icons.check_circle_outline,
          title: 'Completed',
          color: AppColors.growthGreen,
          tasks: completed,
          db: db,
          emptyLabel: 'Nothing completed yet.',
          actions: _RowActions.duplicateOnly,
        ),
        const SizedBox(height: 20),
        _TaskSection(
          icon: Icons.archive_outlined,
          title: 'Archived',
          color: Colors.grey.shade600,
          tasks: archived,
          db: db,
          emptyLabel: 'No archived tasks.',
          archivedDisplay: true,
          actions: _RowActions.duplicateOnly,
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
    required this.actions,
    this.archivedDisplay = false,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<TaskModel> tasks;
  final DatabaseService db;
  final String emptyLabel;
  final _RowActions actions;
  final bool archivedDisplay;

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
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
          )
        else ...[
          const SizedBox(height: 18),

          for (final task in tasks) ...[
            const SizedBox(height:12),
            _TaskProgressRow(
              task: task,
              assignee: _assigneeFor(task),
              db: db,
              actions: actions,
              archivedDisplay: archivedDisplay,
            ),
            const SizedBox(height: 1),
          ],
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
  const _TaskProgressRow({
    required this.task,
    required this.assignee,
    required this.db,
    required this.actions,
    this.archivedDisplay = false,
  });

  final TaskModel task;
  final AppUser? assignee;
  final DatabaseService db;
  final _RowActions actions;
  final bool archivedDisplay;

  Future<void> _reassign(BuildContext context) async {
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Re-assign "${task.title}"'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(_householdPoolSentinel),
            child: const Row(
              children: [
                Icon(Icons.groups_outlined),
                SizedBox(width: 12),
                Text('Household Task (unassigned)'),
              ],
            ),
          ),
          for (final child in db.children)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(child.id),
              child: Row(
                children: [
                  Text(child.avatarEmoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Text(child.name),
                ],
              ),
            ),
        ],
      ),
    );

    if (selection == null || !context.mounted) return;
    final newChildId = selection == _householdPoolSentinel ? null : selection;
    await db.reassignTask(task.id, newChildId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newChildId == null
              ? '"${task.title}" moved back to the household pool.'
              : '"${task.title}" re-assigned to ${db.userById(newChildId)?.name ?? 'a child'}.',
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context) async {
    final duplicate = TaskModel(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: '${task.title} (Copy)',
      description: task.description,
      icon: task.icon,
      assignedToUserId: task.assignedToUserId,
      rewardXp: task.rewardXp,
      coinReward: task.coinReward,
      isRecurring: task.isRecurring,
      createdAt: DateTime.now(),
    );
    final newTaskId = await db.addTask(duplicate);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated as a new pending task - fine-tune it now.')),
    );
    Navigator.of(context).pushNamed(AppRoutes.taskEdit, arguments: newTaskId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: actions == _RowActions.edit
          ? () => Navigator.of(context).pushNamed(AppRoutes.taskEdit, arguments: task.id)
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
                Text(
                  archivedDisplay
                      ? '${assignee?.name ?? 'Household'} • Archived'
                      : '${assignee?.name ?? 'Household'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
                  fontSize: 12),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (archivedDisplay)
                const _ArchivedPill()
              else
                _StatusPill(task: task),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 2),
                  Text('+${task.rewardXp} XP', style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                  )),
                  if (task.coinReward > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.monetization_on, size: 13, color: Colors.amber.shade700),
                    const SizedBox(width: 1),
                    Text('+${task.coinReward}', style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                    )),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(width: 4),
          _TrailingAction(actions: actions, onReassign: () => _reassign(context), onApprove: () => db.approveTask(task.id), onDuplicate: () => _duplicate(context)),
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
    if (difference < 0) return difference == -1 ? 'Past Due by 1 day' : 'Past Due by ${-difference} days';
    if (difference == 0) return 'Due Today';
    if (difference == 1) return 'Due Tomorrow';
    return 'Due in $difference Days';
  }
}

/// The trailing control on a task row, based on [_RowActions].
class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.actions,
    required this.onReassign,
    required this.onApprove,
    required this.onDuplicate,
  });

  final _RowActions actions;
  final VoidCallback onReassign;
  final VoidCallback onApprove;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    switch (actions) {
      case _RowActions.edit:
        return const Icon(Icons.chevron_right, color: Colors.grey, size: 20);
      case _RowActions.approveOrReassign:
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.grey),
          onSelected: (value) {
            if (value == 'approve') onApprove();
            if (value == 'reassign') onReassign();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'approve',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20, color: AppColors.growthGreen),
                  SizedBox(width: 10),
                  Text('Approve'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'reassign',
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, size: 20),
                  SizedBox(width: 10),
                  Text('Re-assign'),
                ],
              ),
            ),
          ],
        );
      case _RowActions.duplicateOnly:
        return IconButton(
          icon: const Icon(Icons.copy_outlined, size: 20, color: Colors.grey),
          tooltip: 'Duplicate',
          onPressed: onDuplicate,
        );
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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

class _ArchivedPill extends StatelessWidget {
  const _ArchivedPill();

  @override
  Widget build(BuildContext context) {
    final color = Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.archive_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Text('Archived', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: AppConstants.captionFontSize)),
        ],
      ),
    );
  }
}
