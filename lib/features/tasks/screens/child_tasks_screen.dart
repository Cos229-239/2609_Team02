import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';

enum _ChildTasksView { tasks, history }

/// "Tasks" tab for a signed-in child — replaces the parent's "Family" tab.
/// A child can see the tasks already claimed/assigned to them, mark them
/// complete, claim new tasks from the household's shared pool, and look
/// back at a history of everything they've completed. They cannot create
/// tasks, assign tasks to anyone else, or manage the family — those
/// actions live only on the parent's screens. The reward catalog and
/// family leaderboard live on the separate Rewards tab.
///
/// This only returns the tab's content; [MainTabShell] supplies the
/// shared app bar, bottom nav bar and [SafeArea].
class ChildTasksScreen extends StatefulWidget {
  const ChildTasksScreen({super.key});

  @override
  State<ChildTasksScreen> createState() => _ChildTasksScreenState();
}

class _ChildTasksScreenState extends State<ChildTasksScreen> {
  _ChildTasksView _view = _ChildTasksView.tasks;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final db = context.watch<DatabaseService>();
    final child = auth.currentUser;

    if (child == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final myTasks = db.tasksForUser(child.id);

    final activeTasks = myTasks
        .where((t) => t.status == TaskStatus.pending)
        .toList(growable: false);

    final awaitingApproval = myTasks
        .where((t) => t.status == TaskStatus.completed)
        .toList(growable: false);

    final availableTasks = db.availableTasks;

    final history = myTasks
        .where((t) => t.status == TaskStatus.approved)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ViewToggle(
          view: _view,
          onChanged: (view) => setState(() => _view = view),
        ),
        const SizedBox(height: 12),
        if (_view == _ChildTasksView.tasks) ...[
          _SectionHeader(
            icon: Icons.check_circle,
            title: 'Claimed / Assigned',
            count: activeTasks.length,
            badgeColor: AppColors.growthGreen,
          ),
          const SizedBox(height: 6),
          if (activeTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Nothing claimed yet — grab a task below!'),
            )
          else
            for (final task in activeTasks) ...[
              _TaskRow(
                task: task,
                trailing: ElevatedButton(
                  onPressed: () =>
                      context.read<DatabaseService>().completeTask(task.id),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                  ),
                  child: const Text('Complete'),
                ),
              ),
              const SizedBox(height: 2),
            ],
          const SizedBox(height: 10),
          _SectionHeader(
            icon: Icons.hourglass_bottom,
            title: 'Awaiting Approval',
            count: awaitingApproval.length,
            badgeColor: Colors.orange,
          ),
          const SizedBox(height: 6),
          if (awaitingApproval.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No tasks waiting for approval.'),
            )
          else
            for (final task in awaitingApproval) ...[
              _TaskRow(
                task: task,
                trailing: const _StatusPill(
                  label: 'Awaiting Approval',
                  color: Colors.orange,
                  icon: Icons.hourglass_bottom,
                ),
              ),
              const SizedBox(height: 2),
            ],
          const SizedBox(height: 10),
          _SectionHeader(
            icon: Icons.access_time,
            title: 'Available Tasks',
            count: availableTasks.length,
            badgeColor: AppColors.primaryBlue,
          ),
          const SizedBox(height: 8),
          if (availableTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No unclaimed tasks right now — check back later!'),
            )
          else
            for (final task in availableTasks) ...[
              _TaskRow(
                task: task,
                isAvailable: true,
                trailing: ElevatedButton(
                  onPressed: () => context.read<DatabaseService>().claimTask(
                    task.id,
                    child.id,
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 24),
                  ),
                  child: const Text('Claim'),
                ),
              ),
              const SizedBox(height: 2),
            ],
        ] else ...[
          _SectionHeader(
            icon: Icons.check_circle_outline,
            title: 'Completed',
            count: history.length,
            badgeColor: AppColors.growthGreen,
          ),
          const SizedBox(height: 6),

          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing completed yet — finish a task to see it here!',
              ),
            )
          else
            for (final task in history) ...[
              _HistoryRow(task: task),
              const SizedBox(height: 12),
            ],
        ],
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _ChildTasksView view;
  final ValueChanged<_ChildTasksView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleButton(
              icon: Icons.check_box,
              label: 'Tasks',
              selected: view == _ChildTasksView.tasks,
              onTap: () => onChanged(_ChildTasksView.tasks),
            ),
          ),
          Expanded(
            child: _ToggleButton(
              icon: Icons.check_circle_outline,
              label: 'Completed',
              selected: view == _ChildTasksView.history,
              onTap: () => onChanged(_ChildTasksView.history),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.badgeColor,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: badgeColor,
            child: Icon(icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.trailing,
    this.isAvailable = false,
  });

  final TaskModel task;
  final Widget trailing;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: isAvailable ? 2 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                (isAvailable
                        ? theme.colorScheme.primary
                        : AppColors.growthGreen)
                    .withValues(alpha: 0.15),
            child: Icon(
              TaskIconCatalog.resolve(task.icon).icon,
              color: AppColors.growthGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${task.isRecurring ? 'Daily Task' : 'One-time Task'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Transform.translate(
                offset: const Offset(8, 0),
                child: trailing,
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 1),
                  Text(
                    '+${task.rewardXp} XP',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dueLabel(DateTime? dueDate) {
    if (dueDate == null) return 'Due Today';
    final today = DateTime.now();
    final difference = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (difference <= 0) return 'Due Today';
    if (difference == 1) return 'Due Tomorrow';
    return 'Due in $difference Days';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.task});

  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approved = task.status == TaskStatus.approved;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),

      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.growthGreen.withValues(alpha: 0.15),
            child: Icon(
              TaskIconCatalog.resolve(task.icon).icon,
              color: AppColors.growthGreen,
              size: 20,
            ),
          ),

          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  task.isRecurring ? 'Daily Task' : 'One-time Task',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusPill(
                label: approved ? 'Approved' : 'Awaiting Approval',
                color: approved ? AppColors.growthGreen : Colors.orange,
                icon: approved ? Icons.check_circle : Icons.hourglass_bottom,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.star, size: 12, color: Colors.amber),
                  const SizedBox(width: 1),
                  Text(
                    '+${task.rewardXp} XP',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
