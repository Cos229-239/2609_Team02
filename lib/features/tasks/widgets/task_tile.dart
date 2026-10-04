import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/task_proof.dart';
import '../../../shared/widgets/app_card.dart';

/// One row representing a task: icon, title, XP reward and a status
/// indicator. Reused by the child's task list and the parent's
/// create/assign screen.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.onTap, this.trailing});

  final TaskModel task;
  final VoidCallback? onTap;

  /// Overrides the default status icon (used by the "assign tasks" screen
  /// to show a toggle/edit/delete row instead of a status indicator).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.secondary.withValues(
              alpha: 0.12,
            ),
            child: Icon(
              TaskIconCatalog.resolve(task.icon).icon,
              color: theme.colorScheme.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (task.requiresPhoto || task.proof != null) ...[
                      const SizedBox(width: 4),
                      _PhotoIndicator(task: task),
                    ],
                  ],
                ),
                if (task.description.isNotEmpty)
                  Text(
                    task.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      '+${task.rewardXp} XP',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                  ],
                ),
                if (task.coinReward > 0) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monetization_on, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 2),
                      Text(
                        '+${task.coinReward}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Transform.translate(
                  offset: Offset(
                    task.status == TaskStatus.completed ? 32 : 0,
                    0,
                  ),
                  child: _StatusBadge(status: task.status),
                  ),
                ),
                ),
          ],
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
      TaskStatus.pending => (
        'To Do',
        Colors.grey,
        Icons.radio_button_unchecked,
      ),
      TaskStatus.completed => (
        'Pending Approval',
        Colors.orange,
        Icons.hourglass_bottom,
      ),
      TaskStatus.approved => ('Done', Colors.green, Icons.check_circle),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: AppConstants.captionFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoIndicator extends StatelessWidget {
  const _PhotoIndicator({required this.task});

  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    final proof = task.proof;
    final (Color color, String tip) = switch (proof?.verdict) {
      null => (Colors.grey.shade500, 'Photo proof required'),
      ScanVerdict.match => (Colors.green.shade600, 'Photo looks like a match'),
      ScanVerdict.noMatch => (Colors.red.shade600, "Photo doesn't look related - check it"),
      final ScanVerdict v => (Colors.orange.shade700, '${v.label} - check the photo'),
    };
    return Tooltip(
      message: tip,
      child: Icon(
        Icons.photo_camera_outlined,
        key: const ValueKey('task-photo-indicator'),
        size: 14,
        color: color,
      ),
    );
  }
}
