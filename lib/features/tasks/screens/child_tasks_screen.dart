import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/help_tip.dart';
import '../widgets/task_swipe.dart';
import '../widgets/task_view_card.dart';
import '../../../core/services/accessibility_settings.dart';

enum _ChildTasksView { tasks, history }

/// "Tasks" tab for a signed-in child: claimed/assigned tasks, tasks
/// available to claim, and a completion history. Task/family management
/// stays parent-only; the reward catalog lives on the Rewards tab.
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
        const SizedBox(height: 8),
        Text(
          _view == _ChildTasksView.tasks
              ? (AccessibilitySettings.swipesEnabled(context)
                  ? 'Tap a task to see it, or swipe right to claim or complete it.'
                  : 'Tap a task to see it and claim or complete it.')
              : 'Tasks approved in the last ${AppConstants.doneTaskVisibleDays} days.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        if (_view == _ChildTasksView.tasks) ...[
          _TaskDrawer(
            key: const ValueKey('drawer-claimed'),
            icon: Icons.check_circle,
            title: 'Claimed / Assigned',
            count: activeTasks.length,
            badgeColor: AppColors.growthGreen,
            help: 'Your tasks. Tap one to mark it complete when you finish.',
            emptyLabel: 'Nothing claimed yet - grab a task below!',
            initiallyExpanded: true,
            children: [
              for (final task in activeTasks) _TaskRow(task: task, childId: child.id),
            ],
          ),
          const SizedBox(height: 10),
          _TaskDrawer(
            key: const ValueKey('drawer-awaiting'),
            icon: Icons.hourglass_bottom,
            title: 'Awaiting Approval',
            count: awaitingApproval.length,
            badgeColor: Colors.orange,
            help: 'Done and waiting for a parent to check. You get the XP and coins once it\'s approved.',
            emptyLabel: 'No tasks waiting for approval.',
            children: [
              for (final task in awaitingApproval)
                _TaskRow(
                  task: task,
                  childId: child.id,
                  trailing: const _StatusPill(
                    label: 'Awaiting Approval',
                    color: Colors.orange,
                    icon: Icons.hourglass_bottom,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _TaskDrawer(
            key: const ValueKey('drawer-available'),
            icon: Icons.access_time,
            title: 'Available Tasks',
            count: availableTasks.length,
            badgeColor: AppColors.primaryBlue,
            help: 'Household tasks anyone can do. Claim one to make it yours - first come, first served!',
            emptyLabel: 'No unclaimed tasks right now - check back later!',
            // Nothing to do yet? Show what's up for grabs.
            initiallyExpanded: activeTasks.isEmpty,
            children: [
              for (final task in availableTasks)
                _TaskRow(task: task, childId: child.id, isAvailable: true),
            ],
          ),
        ] else ...[
          _TaskDrawer(
            key: const ValueKey('drawer-completed'),
            icon: Icons.check_circle_outline,
            title: 'Completed',
            count: history.length,
            badgeColor: AppColors.growthGreen,
            emptyLabel: 'Nothing completed yet - finish a task to see it here!',
            initiallyExpanded: true,
            children: [
              for (final task in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryRow(task: task),
                ),
            ],
          ),
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
        color: context.mutedFill,
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
                color: selected ? Colors.white : (context.isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : (context.isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700),
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
    this.help,
    this.expanded,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color badgeColor;

  /// Drawer state for the arrow; null hides the arrow.
  final bool? expanded;

  /// Optional ⓘ tip explaining this section.
  final String? help;

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
            child: help == null
                ? Text(title, style: Theme.of(context).textTheme.titleMedium)
                : HeadingWithHelp(
                    heading: Text(title, style: Theme.of(context).textTheme.titleMedium),
                    helpTitle: title,
                    help: help!,
                  ),
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
          if (expanded != null) ...[
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: expanded! ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}

/// A collapsible section: tapping the header slides its tasks open or
/// closed. The count stays visible on the header while it's closed.
class _TaskDrawer extends StatefulWidget {
  const _TaskDrawer({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.badgeColor,
    required this.emptyLabel,
    required this.children,
    this.help,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color badgeColor;
  final String emptyLabel;
  final List<Widget> children;
  final String? help;
  final bool initiallyExpanded;

  @override
  State<_TaskDrawer> createState() => _TaskDrawerState();
}

class _TaskDrawerState extends State<_TaskDrawer> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: _SectionHeader(
              icon: widget.icon,
              title: widget.title,
              count: widget.count,
              badgeColor: widget.badgeColor,
              help: widget.help,
              expanded: _expanded,
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
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: widget.children.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            child: Text(widget.emptyLabel),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.children,
                          ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    this.trailing,
    this.childId,
    this.isAvailable = false,
  });

  final TaskModel task;
  /// Optional status shown in place of the rewards (e.g. "Awaiting Approval").
  /// Actions like claim/complete live in the task view card instead.
  final Widget? trailing;

  /// Enables swipe actions (claim / complete / undo) for this child.
  final String? childId;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final id = childId;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTaskViewSheet(context, task.id),
      child: _buildRow(context),
    );
    if (id == null) return row;
    return ChildTaskSwipe(task: task, childId: id, child: row);
  }

  Widget _buildRow(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12.5, 25, 25, 25),
      decoration: BoxDecoration(
        color: context.raisedSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.subtleBorder),
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
                  '${task.repeatLabel} • ${_dueLabel(task.dueDate)}',
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
              // A status (e.g. "Awaiting Approval") takes the rewards' place.
              if (trailing != null)
                trailing!
              else
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
                  if (task.coinReward > 0) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.monetization_on, size: 12, color: Colors.amber.shade800),
                    const SizedBox(width: 1),
                    Text(
                      '+${task.coinReward}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
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
    if (difference < 0) return 'Past Due';
    if (difference == 0) return 'Due Today';
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTaskViewSheet(context, task.id),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.raisedSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.isDarkMode ? Colors.black26 : Colors.grey.shade200,
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
                  task.repeatLabel,
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
              if (task.coinReward > 0) ...[
                const SizedBox(height: 1),
                Row(
                  children: [
                    Icon(Icons.monetization_on, size: 12, color: Colors.amber.shade800),
                    const SizedBox(width: 1),
                    Text(
                      '+${task.coinReward}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    ),
    );
  }
}
