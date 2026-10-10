import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../task_completion_flow.dart';

/// One swipe direction's action: the colored background that's revealed
/// and what happens when the swipe goes past the threshold.
class TaskSwipeAction {
  const TaskSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTriggered,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Runs the action. Return false to leave the task untouched (e.g. a
  /// "Delete?" confirmation was cancelled).
  final Future<bool> Function() onTriggered;
}

/// Wraps a task row so it can be swiped: right ([startToEnd]) for the
/// task's main action (approve, complete, claim, ...), left ([endToStart])
/// for the secondary/destructive one (delete, undo).
///
/// The row is never removed by the swipe itself: it springs back, and the
/// Firestore listener moves/removes it once the change lands.
class TaskSwipe extends StatelessWidget {
  const TaskSwipe({
    super.key,
    required this.task,
    required this.child,
    this.startToEnd,
    this.endToStart,
  });

  final TaskModel task;
  final Widget child;
  final TaskSwipeAction? startToEnd;
  final TaskSwipeAction? endToStart;

  @override
  Widget build(BuildContext context) {
    final right = startToEnd;
    final left = endToStart;
    if (right == null && left == null) return child;

    final direction = right != null && left != null
        ? DismissDirection.horizontal
        : (right != null ? DismissDirection.startToEnd : DismissDirection.endToStart);

    return Dismissible(
      key: ValueKey('swipe-${task.id}'),
      direction: direction,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      background: right == null ? const SizedBox.shrink() : _SwipeBackground(action: right, alignStart: true),
      secondaryBackground: left == null ? null : _SwipeBackground(action: left, alignStart: false),
      confirmDismiss: (dir) async {
        final action = dir == DismissDirection.startToEnd ? right : left;
        if (action == null) return false;
        try {
          await action.onTriggered();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
            );
          }
        }
        return false;
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.action, required this.alignStart});

  final TaskSwipeAction action;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    final content = [
      Icon(action.icon, color: Colors.white),
      const SizedBox(width: 8),
      Text(action.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: action.color, borderRadius: BorderRadius.circular(16)),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignStart ? content : content.reversed.toList(),
      ),
    );
  }
}

/// Swipe actions for a parent: right approves a task awaiting approval
/// (otherwise archives / unarchives it), left deletes it after confirming.
({TaskSwipeAction? startToEnd, TaskSwipeAction? endToStart}) parentTaskSwipeActions(
  BuildContext context,
  TaskModel task,
) {
  // Looked up when a swipe fires, not while building (provider's read()
  // isn't allowed during build).
  DatabaseService db() => context.read<DatabaseService>();
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  final TaskSwipeAction primary;
  if (task.status == TaskStatus.completed) {
    primary = TaskSwipeAction(
      label: 'Approve',
      icon: Icons.check_circle,
      color: AppColors.growthGreen,
      onTriggered: () async {
        await db().approveTask(task.id);
        say('"${task.title}" approved - rewards granted!');
        return true;
      },
    );
  } else {
    final unarchive = task.archived;
    primary = TaskSwipeAction(
      label: unarchive ? 'Unarchive' : 'Archive',
      icon: unarchive ? Icons.unarchive_outlined : Icons.archive_outlined,
      color: Colors.blueGrey,
      onTriggered: () async {
        await db().setTaskArchived(task.id, !unarchive);
        say(unarchive ? '"${task.title}" unarchived.' : '"${task.title}" archived.');
        return true;
      },
    );
  }

  final delete = TaskSwipeAction(
    label: 'Delete',
    icon: Icons.delete_outline,
    color: Colors.red,
    onTriggered: () async {
      final confirmed = await confirmDeleteTask(context, task);
      if (!confirmed) return false;
      await db().removeTask(task.id);
      say('"${task.title}" deleted.');
      return true;
    },
  );

  return (startToEnd: primary, endToStart: delete);
}

/// Swipe actions for a child: right claims a pool task or completes their
/// own; left takes back a "done" that's still awaiting approval.
({TaskSwipeAction? startToEnd, TaskSwipeAction? endToStart}) childTaskSwipeActions(
  BuildContext context,
  TaskModel task,
  String childId,
) {
  DatabaseService db() => context.read<DatabaseService>();
  if (task.isAvailable) {
    return (
      startToEnd: TaskSwipeAction(
        label: 'Claim',
        icon: Icons.pan_tool_alt_outlined,
        color: AppColors.primaryBlue,
        onTriggered: () async {
          await db().claimTask(task.id, childId);
          return true;
        },
      ),
      endToStart: null,
    );
  }
  switch (task.status) {
    case TaskStatus.pending:
      final needsPhoto = Provider.of<DatabaseService>(context, listen: false).needsPhoto(task);
      return (
        startToEnd: TaskSwipeAction(
          label: needsPhoto ? 'Add Photo' : 'Complete',
          icon: needsPhoto ? Icons.photo_camera : Icons.check_circle,
          color: AppColors.growthGreen,
          // Photo-proof tasks open the camera flow instead.
          onTriggered: () => startTaskCompletion(context, task),
        ),
        endToStart: null,
      );
    case TaskStatus.completed:
      return (
        startToEnd: null,
        endToStart: TaskSwipeAction(
          label: 'Not done yet',
          icon: Icons.undo,
          color: Colors.orange,
          onTriggered: () async {
            await db().uncompleteTask(task.id);
            return true;
          },
        ),
      );
    case TaskStatus.approved:
      return (startToEnd: null, endToStart: null);
  }
}

Future<bool> confirmDeleteTask(BuildContext context, TaskModel task) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Task?'),
      content: Text('This permanently removes "${task.title}". This can\'t be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Convenience: a [TaskSwipe] with [parentTaskSwipeActions].
class ParentTaskSwipe extends StatelessWidget {
  const ParentTaskSwipe({super.key, required this.task, required this.child});

  final TaskModel task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final actions = parentTaskSwipeActions(context, task);
    return TaskSwipe(task: task, startToEnd: actions.startToEnd, endToStart: actions.endToStart, child: child);
  }
}

/// Convenience: a [TaskSwipe] with [childTaskSwipeActions].
class ChildTaskSwipe extends StatelessWidget {
  const ChildTaskSwipe({super.key, required this.task, required this.childId, required this.child});

  final TaskModel task;
  final String childId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final actions = childTaskSwipeActions(context, task, childId);
    return TaskSwipe(task: task, startToEnd: actions.startToEnd, endToStart: actions.endToStart, child: child);
  }
}
