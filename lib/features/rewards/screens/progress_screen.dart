import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/help_tip.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/user.dart';
import '../../../core/services/database_service.dart';
import '../../rex/rex_kid_mode.dart';
import '../../tasks/widgets/task_swipe.dart';
import '../../../shared/widgets/app_card.dart';
import '../../tasks/widgets/task_view_card.dart';
import '../../../core/services/accessibility_settings.dart';

/// Distinct from `null` (dialog dismissed without a choice).

/// What a task row's trailing action does, based on its section.

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
  HeadingWithHelp(
    heading: Text(
      'Family Progress',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
    ),
    helpTitle: 'Family Progress',
    help: "Each child's lifetime XP and current coin balance. XP only goes up; "
        'coins go down when a reward is redeemed. Tap a child to open Rex\'s Room '
        'for them on this device.',
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
            key: Key('progress-child-${child.id}'),
            onTap: () => startRexKidMode(context, child),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
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
                const SizedBox(height: 1),
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
        HeadingWithHelp(
          heading: Text('All Tasks:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          )),
          helpTitle: 'All Tasks',
          help: 'Every task in the household, grouped by status. Tap a task to approve, '
              'edit, re-assign or duplicate it.',
        ),
        const SizedBox(height: 4),
        Text(
          '${AccessibilitySettings.swipesEnabled(context) ? 'Tap a task to see it. Swipe right to approve/archive, left to delete.' : 'Tap to view tasks.'} '
          'Completed tasks show for '
          '${AppConstants.doneTaskVisibleDays} days; all tasks are deleted '
          'after ${AppConstants.taskDeleteAfterDays} days.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        _TaskSection(
          icon: Icons.hourglass_bottom,
          title: 'Awaiting Approval',
          color: Colors.orange,
          tasks: awaitingApproval,
          db: db,
          emptyLabel: 'No tasks waiting for approval.',
          initiallyExpanded: awaitingApproval.isNotEmpty,
        ),
        const SizedBox(height: 10),
        _TaskSection(
          icon: Icons.error_outline,
          title: 'Overdue',
          color: Colors.red.shade600,
          tasks: overdue,
          db: db,
          emptyLabel: 'Nothing overdue - nice work!',
          initiallyExpanded: overdue.isNotEmpty,
        ),
        const SizedBox(height: 10),
        _TaskSection(
          icon: Icons.schedule,
          title: 'Pending',
          color: AppColors.primaryBlue,
          tasks: pending,
          db: db,
          emptyLabel: 'No pending tasks right now.',
        ),
        const SizedBox(height: 10),
        _TaskSection(
          icon: Icons.check_circle_outline,
          title: 'Completed',
          color: AppColors.growthGreen,
          tasks: completed,
          db: db,
          emptyLabel: 'Nothing completed yet.',
        ),
        const SizedBox(height: 10),
        _TaskSection(
          icon: Icons.archive_outlined,
          title: 'Archived',
          color: Colors.grey.shade600,
          tasks: archived,
          db: db,
          emptyLabel: 'No archived tasks.',
          archivedDisplay: true,
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

/// A collapsible "drawer" for one status group: tapping the header slides
/// its tasks open or closed. The header always shows the task count, so a
/// closed drawer still tells the parent whether anything is inside.
class _TaskSection extends StatefulWidget {
  const _TaskSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.tasks,
    required this.db,
    required this.emptyLabel,
    this.archivedDisplay = false,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<TaskModel> tasks;
  final DatabaseService db;
  final String emptyLabel;
  final bool archivedDisplay;
  final bool initiallyExpanded;

  @override
  State<_TaskSection> createState() => _TaskSectionState();
}

class _TaskSectionState extends State<_TaskSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final tasks = widget.tasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Semantics(
              button: true,
              expanded: _expanded,
              label: '${widget.title}, ${tasks.length} tasks',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(radius: 12, backgroundColor: color, child: Icon(widget.icon, size: 14, color: Colors.white)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                      child: Text('${tasks.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : tasks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        child: Text(widget.emptyLabel, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final task in tasks) ...[
                            const SizedBox(height: 12),
                            ParentTaskSwipe(
                              task: task,
                              child: _TaskProgressRow(
                                task: task,
                                assignee: _assigneeFor(task),
                                db: widget.db,
                                archivedDisplay: widget.archivedDisplay,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  AppUser? _assigneeFor(TaskModel task) {
    if (task.assignedToUserId == null) return null;
    return widget.db.userById(task.assignedToUserId!);
  }
}

class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({
    required this.task,
    required this.assignee,
    required this.db,
    this.archivedDisplay = false,
  });

  final TaskModel task;
  final AppUser? assignee;
  final DatabaseService db;
  final bool archivedDisplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: () => showTaskViewSheet(context, task.id),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
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
                  archivedDisplay
                      ? '${assignee?.name ?? 'Household'} • Archived'
                      : '${assignee?.name ?? 'Household'} • ${_dueLabel(task.dueDate)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
                  fontSize: 13),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (archivedDisplay)
            const _ArchivedPill()
          else
            _StatusPill(task: task),
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
