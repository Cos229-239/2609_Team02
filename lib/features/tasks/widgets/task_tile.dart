import 'package:flutter/material.dart';

import '../../../core/models/task.dart';
import '../../../shared/widgets/app_card.dart';

/// One row representing a task: icon, title, XP reward and a status
/// indicator. Reused by the child's task list and the parent's
/// create/assign screen.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.trailing,
  });

  final TaskModel task;
  final VoidCallback? onTap;

  /// Overrides the default status icon (used by the "assign tasks" screen
  /// to show a toggle/edit/delete row instead of a status indicator).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.12),
            child: Text(task.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: theme.textTheme.titleMedium),
                if (task.description.isNotEmpty)
                  Text(
                    task.description,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text('${task.rewardXp} XP', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 4),
                _StatusBadge(status: task.status),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      TaskStatus.pending => ('To Do', Colors.grey, Icons.radio_button_unchecked),
      TaskStatus.completed => ('Pending Approval', Colors.orange, Icons.hourglass_bottom),
      TaskStatus.approved => ('Done', Colors.green, Icons.check_circle),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
