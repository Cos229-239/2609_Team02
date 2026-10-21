import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../task_completion_flow.dart';
import 'task_proof_card.dart';
import '../../../shared/widgets/app_notice.dart';

/// Opens the task view card for [taskId] as a bottom sheet over the current
/// screen. Used when tapping a task tile anywhere in the app.
Future<void> showTaskViewSheet(BuildContext context, String taskId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, controller) => TaskViewCard(
        taskId: taskId,
        scrollController: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
    ),
  );
}

/// The task's details plus the actions that fit the viewer and the task's
/// status:
/// - child: claim, mark complete / take photo, or see where it stands
/// - parent: mark complete or edit (pending), approve or send back
///   (awaiting approval)
///
/// Shown in a bottom sheet ([showTaskViewSheet]) or as the body of
/// [TaskDetailScreen]. Actions that finish the task close whichever route
/// the card lives in.
class TaskViewCard extends StatelessWidget {
  const TaskViewCard({
    super.key,
    required this.taskId,
    this.scrollController,
    this.padding = const EdgeInsets.all(20),
  });

  final String taskId;
  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final viewer = context.watch<AuthService>().currentUser;
    final isParent = viewer?.isParent ?? false;

    TaskModel? found;
    for (final t in db.tasks) {
      if (t.id == taskId) {
        found = t;
        break;
      }
    }
    if (found == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Task not found.')),
      );
    }
    final task = found;
    final theme = Theme.of(context);
    final assignee = task.assignedToUserId == null ? null : db.userById(task.assignedToUserId!);

    return ListView(
      controller: scrollController,
      padding: padding,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.15),
                    child: Icon(
                      TaskIconCatalog.resolve(task.icon).icon,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.title, style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${assignee?.name ?? 'Household task'} • ${_statusLabel(task)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(task.description, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _Fact(
                    icon: const Icon(Icons.star, color: Colors.amber, size: 20),
                    label: '+${task.rewardXp} XP',
                  ),
                  if (task.coinReward > 0)
                    _Fact(
                      icon: Icon(Icons.monetization_on, color: Colors.amber.shade700, size: 20),
                      label: '+${task.coinReward} coins',
                    ),
                  if (task.dueDate != null)
                    _Fact(
                      icon: Icon(Icons.event_outlined, color: Colors.grey.shade600, size: 18),
                      label: _dueLabel(task.dueDate!),
                    ),
                  if (task.repeat != null)
                    _Fact(
                      icon: Icon(Icons.repeat, color: Colors.grey.shade600, size: 18),
                      label: task.repeatLabel,
                    ),
                  if (db.needsPhoto(task))
                    _Fact(
                      icon: Icon(Icons.photo_camera_outlined, color: Colors.grey.shade600, size: 18),
                      label: 'Photo proof required',
                    ),
                ],
              ),
            ],
          ),
        ),
        if (isParent && task.proof != null && task.status != TaskStatus.pending) ...[
          const SizedBox(height: 16),
          TaskProofCard(proof: task.proof!),
        ],
        const SizedBox(height: 20),
        ...(isParent ? _parentActions(context, task) : _childActions(context, task, viewer?.id)),
      ],
    );
  }

  List<Widget> _parentActions(BuildContext context, TaskModel task) {
    return [
      ..._parentPrimaryActions(context, task),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (task.status != TaskStatus.approved && !task.archived)
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 20),
              label: const Text('Re-assign'),
              onPressed: () => _reassign(context, task),
            ),
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Duplicate'),
            onPressed: () => _duplicate(context, task),
          ),
        ],
      ),
    ];
  }

  List<Widget> _parentPrimaryActions(BuildContext context, TaskModel task) {
    final edit = AppButton(
      label: 'Edit Task',
      icon: Icons.edit_outlined,
      variant: AppButtonVariant.secondary,
      onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.taskEdit, arguments: task.id),
    );

    switch (task.status) {
      case TaskStatus.pending:
        return [
          // Pool tasks have no child to reward, so they're only editable.
          if (!task.isAvailable) ...[
            AppButton(
              label: 'Mark as Complete',
              icon: Icons.check_circle_outline,
              variant: AppButtonVariant.success,
              onPressed: () => _parentComplete(context, task),
            ),
            const SizedBox(height: 8),
          ],
          edit,
        ];
      case TaskStatus.completed:
        return [
          AppButton(
            label: task.proofNeedsReview ? 'Approve Anyway' : 'Approve Task',
            icon: Icons.check_circle_outline,
            variant: AppButtonVariant.success,
            onPressed: () async {
              await context.read<DatabaseService>().approveTask(task.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Send Back to Redo',
            icon: Icons.undo,
            variant: AppButtonVariant.secondary,
            onPressed: () => _confirmSendBack(context, task),
          ),
        ];
      case TaskStatus.approved:
        return const [Center(child: Text('✅ Completed & approved'))];
    }
  }

  List<Widget> _childActions(BuildContext context, TaskModel task, String? childId) {
    switch (task.status) {
      case TaskStatus.pending when task.isAvailable:
        return [
          AppButton(
            label: 'Claim Task',
            icon: Icons.front_hand_outlined,
            onPressed: childId == null
                ? null
                : () async {
                    await context.read<DatabaseService>().claimTask(task.id, childId);
                    if (!context.mounted) return;
                    showAppNotice(context, '"${task.title}" is yours now!');
                  },
          ),
        ];
      case TaskStatus.pending:
        final photo = context.read<DatabaseService>().needsPhoto(task);
        return [
          AppButton(
            label: photo ? 'Take Photo to Finish' : 'Mark as Complete',
            icon: photo ? Icons.photo_camera : Icons.check_circle_outline,
            variant: AppButtonVariant.success,
            onPressed: () async {
              final navigator = Navigator.of(context);
              final done = await startTaskCompletion(context, task, celebrate: true);
              // The no-photo path replaces this route with the celebration;
              // after a photo is sent we're still here, so close the card.
              if (done && context.mounted && navigator.canPop()) navigator.pop();
            },
          ),
        ];
      case TaskStatus.completed:
        return [
          const Center(child: Text('⏳ Waiting for a parent to approve')),
          const SizedBox(height: 12),
          AppButton(
            label: 'Not Done Yet',
            icon: Icons.undo,
            variant: AppButtonVariant.secondary,
            onPressed: () async {
              await context.read<DatabaseService>().uncompleteTask(task.id);
              if (!context.mounted) return;
              showAppNotice(context, '"${task.title}" is back on your list.');
            },
          ),
        ];
      case TaskStatus.approved:
        return const [Center(child: Text('✅ Completed & approved'))];
    }
  }

  Future<void> _reassign(BuildContext context, TaskModel task) async {
    final db = context.read<DatabaseService>();
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Re-assign "${task.title}"'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(_householdPool),
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
    final newChildId = selection == _householdPool ? null : selection;
    await db.reassignTask(task.id, newChildId);
    if (!context.mounted) return;
    showAppNotice(context, newChildId == null
              ? '"${task.title}" moved back to the household pool.'
              : '"${task.title}" re-assigned to ${db.userById(newChildId)?.name ?? 'a child'}.',);
  }

  Future<void> _duplicate(BuildContext context, TaskModel task) async {
    final duplicate = TaskModel(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: '${task.title} (Copy)',
      description: task.description,
      icon: task.icon,
      assignedToUserId: task.assignedToUserId,
      rewardXp: task.rewardXp,
      coinReward: task.coinReward,
      createdAt: DateTime.now(),
    );
    final newTaskId = await context.read<DatabaseService>().addTask(duplicate);
    if (!context.mounted) return;
    showAppNotice(context, 'Duplicated as a new pending task - fine-tune it now.');
    // Swap this card for the copy's editor.
    Navigator.of(context).pushReplacementNamed(AppRoutes.taskEdit, arguments: newTaskId);
  }

  /// A parent finishing a task themselves needs no separate approval: it's
  /// approved and rewarded in one step (photo proof is skipped too).
  Future<void> _parentComplete(BuildContext context, TaskModel task) async {
    final notices = AppNotice.of(context);
    final navigator = Navigator.of(context);
    await context.read<DatabaseService>().parentCompleteTask(task.id);
    notices.show('"${task.title}" completed - rewards granted!', tone: NoticeTone.success);
    if (navigator.mounted) navigator.pop();
  }

  Future<void> _confirmSendBack(BuildContext context, TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send Back?'),
        content: Text(
          '"${task.title}" goes back to the to-do list'
          '${task.proof != null ? ' and the photo is deleted' : ''}. No rewards are given.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Send Back')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<DatabaseService>().uncompleteTask(task.id);
    if (!context.mounted) return;
    showAppNotice(context, '"${task.title}" sent back to redo.', tone: NoticeTone.success);
    Navigator.of(context).pop();
  }

  static String _statusLabel(TaskModel task) {
    if (task.archived) return 'Archived';
    return switch (task.status) {
      TaskStatus.pending => task.isAvailable ? 'Up for grabs' : 'To do',
      TaskStatus.completed => 'Awaiting approval',
      TaskStatus.approved => 'Done',
    };
  }

  static String _dueLabel(DateTime due) {
    final now = DateTime.now();
    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return days == -1 ? 'Past due by 1 day' : 'Past due by ${-days} days';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'Due in $days days';
  }
}

const String _householdPool = '__household_pool__';

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
