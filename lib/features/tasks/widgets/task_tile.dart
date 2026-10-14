import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/task_proof.dart';
import '../../../shared/widgets/app_card.dart';

/// One row representing a task in a parent's view: icon, title and a
/// status indicator. Rewards aren't shown here (parents see them on the
/// task card); tapping the tile opens that card.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onTap,
    this.completedByName,
    this.showDescription = true,
  });

  final TaskModel task;
  final VoidCallback? onTap;

  /// When set, shows "Completed by <name>" under the title (parent approval
  /// views).
  final String? completedByName;

  /// Hides the description line for compact lists like "Needs Approval".
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = Colors.grey.shade600;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 14,
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
        if (completedByName != null) ...[
          const SizedBox(height: 2),
          Text(
            'Completed by $completedByName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: muted),
          ),
        ],
        if (showDescription && task.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            task.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12, color: muted),
          ),
        ],
      ],
    );

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
          const SizedBox(width: 10),
          // No action buttons here: tapping the tile opens the task card.
          Expanded(flex: 7, child: details),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: _StatusBadge(status: task.status),
            ),
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
            softWrap: true,
            textAlign: TextAlign.end,
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
