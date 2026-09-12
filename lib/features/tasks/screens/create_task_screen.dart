import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../widgets/task_tile.dart';

/// "Parent assigning tasks" — pick a child, review/toggle their tasks and
/// assign new ones, then optionally jump into choosing rewards for them.
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key, this.initialChildId});

  final String? initialChildId;

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  String? _selectedChildId;
  final Set<String> _enabledTaskIds = {};

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final children = db.children;

    _selectedChildId ??= widget.initialChildId ?? (children.isNotEmpty ? children.first.id : null);
    final selectedChild = _selectedChildId == null ? null : db.userById(_selectedChildId!);
    final List<TaskModel> tasks =
        _selectedChildId == null ? const [] : db.tasksForUser(_selectedChildId!);

    if (_enabledTaskIds.isEmpty && tasks.isNotEmpty) {
      _enabledTaskIds.addAll(tasks.map((t) => t.id));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Assign Tasks')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Assign Tasks to', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedChild?.id,
              items: [
                for (final child in children)
                  DropdownMenuItem(value: child.id, child: Text('${child.name} (Age ${child.age ?? '—'})')),
              ],
              onChanged: (value) => setState(() {
                _selectedChildId = value;
                _enabledTaskIds.clear();
              }),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tasks', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: selectedChild == null ? null : () => _showAddTaskDialog(context, selectedChild.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Task'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No tasks yet — add one above.'),
              )
            else
              for (final task in tasks) ...[
                TaskTile(
                  task: task,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _enabledTaskIds.contains(task.id),
                        onChanged: (value) => setState(() {
                          value ? _enabledTaskIds.add(task.id) : _enabledTaskIds.remove(task.id);
                        }),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => context.read<DatabaseService>().removeTask(task.id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 24),
            AppButton(
              label: 'Assign Task',
              icon: Icons.send,
              onPressed: selectedChild == null
                  ? null
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Tasks assigned to ${selectedChild.name}!')),
                      );
                    },
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Assign Rewards',
              variant: AppButtonVariant.success,
              icon: Icons.card_giftcard,
              onPressed: selectedChild == null
                  ? null
                  : () => Navigator.of(context).pushNamed(AppRoutes.rewardChoose, arguments: selectedChild.id),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context, String childId) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Task name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                context.read<DatabaseService>().addTask(
                      TaskModel(
                        id: 'task-${DateTime.now().millisecondsSinceEpoch}',
                        title: title,
                        assignedToUserId: childId,
                      ),
                    );
              }
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
