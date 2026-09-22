import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/description_suggester.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/number_stepper.dart';

enum _AssignTarget { household, child }

/// "Create Task" / "Edit Task" screen. Passing [taskId] switches it into
/// edit mode, pre-filled from the existing task.
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key, this.initialChildId, this.taskId});

  /// Pre-selects a child instead of defaulting to "household". Ignored
  /// when [taskId] is set.
  final String? initialChildId;

  /// When set, edits this task instead of creating a new one.
  final String? taskId;

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _selectedIconKey;
  DateTime? _dueDate;
  late bool _isRecurring;
  late int _xp;
  late int _coins;
  // Set in initState: widget isn't accessible from field initializers.
  late _AssignTarget _assignTarget;
  String? _selectedChildId;

  /// The task being edited, or null when creating a new one.
  TaskModel? _originalTask;

  bool get _isEditing => _originalTask != null;

  @override
  void initState() {
    super.initState();

    TaskModel? existing;
    if (widget.taskId != null) {
      final db = context.read<DatabaseService>();
      for (final t in db.tasks) {
        if (t.id == widget.taskId) {
          existing = t;
          break;
        }
      }
    }
    _originalTask = existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _selectedIconKey = existing?.icon ?? TaskIconCatalog.defaultKey;
    _dueDate = existing?.dueDate;
    _isRecurring = existing?.isRecurring ?? false;
    _xp = existing?.rewardXp ?? AppConstants.defaultTaskXp;
    _coins = existing?.coinReward ?? AppConstants.defaultTaskCoins;
    _selectedChildId = existing?.assignedToUserId ?? widget.initialChildId;
    _assignTarget = _selectedChildId != null ? _AssignTarget.child : _AssignTarget.household;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _titleController.text.trim().isNotEmpty;

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _applySuggestedDescription() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _descriptionController.text = DescriptionSuggester.suggest(
        title: title,
        iconKey: _selectedIconKey,
      );
    });
  }

  void _submit(DatabaseService db) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final assignedToUserId = _assignTarget == _AssignTarget.household ? null : _selectedChildId;
    final description = _descriptionController.text.trim();
    final original = _originalTask;

    if (original != null) {
      final updated = original.copyWith(
        title: title,
        description: description,
        icon: _selectedIconKey,
        assignedToUserId: assignedToUserId,
        clearAssignedToUserId: assignedToUserId == null,
        rewardXp: _xp,
        coinReward: _coins,
        isRecurring: _isRecurring,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
      );
      db.updateTask(original.id, updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" updated!')),
      );
    } else {
      db.addTask(
        TaskModel(
          id: 'task-${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          description: description,
          icon: _selectedIconKey,
          assignedToUserId: assignedToUserId,
          dueDate: _dueDate,
          isRecurring: _isRecurring,
          rewardXp: _xp,
          coinReward: _coins,
          createdAt: DateTime.now(),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" created!')),
      );
    }

    Navigator.of(context).pop();
  }

  Future<void> _toggleArchived() async {
    final task = _originalTask;
    if (task == null) return;
    final newValue = !task.archived;
    await context.read<DatabaseService>().setTaskArchived(task.id, newValue);
    if (!mounted) return;
    setState(() => _originalTask = task.copyWith(archived: newValue));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(newValue ? 'Task archived.' : 'Task unarchived.')),
    );
  }

  Future<void> _confirmDelete() async {
    final task = _originalTask;
    if (task == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text(
          'This permanently removes "${task.title}". This can\'t be undone.',
        ),
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

    if (confirmed != true || !mounted) return;

    await context.read<DatabaseService>().removeTask(task.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final children = db.children;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Task' : 'Create Task'),
        actions: [
          if (_isEditing)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'archive') _toggleArchived();
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(
                        _originalTask!.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(_originalTask!.archived ? 'Unarchive Task' : 'Archive Task'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Delete Task', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            if (_isEditing && _originalTask!.isArchived) ...[
              AppCard(
                color: Colors.orange.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _originalTask!.archived
                            ? 'This task is archived.'
                            : 'This task auto-archived - it\'s more than ${AppConstants.taskArchiveAfterDays} days old.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text('Choose an Icon:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            ),
            const SizedBox(height: 12),
            _IconPicker(
              selectedKey: _selectedIconKey,
              onSelected: (key) => setState(() => _selectedIconKey = key),
            ),
            const SizedBox(height: 16),
            Text('Name this Task:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              autofocus: !_isEditing,
              decoration: const InputDecoration(hintText: 'e.g. Take Out the Trash'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('Description (optional):', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                TextButton.icon(
                  onPressed: _canSubmit ? _applySuggestedDescription : null,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Suggest'),
                ),
              ],
            ),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What does "done" look like for this task?',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Suggestions come from an on-device assistant - nothing leaves this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11),
            ),
            const SizedBox(height: 20),
            Text('Rewards for Completing This Task:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 8),
            NumberStepper(
              label: 'XP Earned',
              icon: Icons.star,
              iconColor: Colors.amber,
              value: _xp,
              step: 5,
              max: 1000,
              onChanged: (value) => setState(() => _xp = value),
            ),
            const SizedBox(height: 8),
            NumberStepper(
              label: 'Coins Earned',
              icon: Icons.monetization_on,
              iconColor: Colors.amber.shade700,
              value: _coins,
              step: 5,
              max: 1000,
              onChanged: (value) => setState(() => _coins = value),
            ),
            const SizedBox(height: 20),
            Text('Select a Due Date:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            ),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              onTap: _pickDueDate,
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dueDate == null ? 'No due date - tap to set one' : _formatDate(_dueDate!),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _dueDate = null),
                    )
                  else
                    const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.repeat, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Repeat this task?', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                        Text(
                          'If selected: This task will repeat when task is complete.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600,
                          fontSize: 12,)
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isRecurring,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFF4CAF50),
                    onChanged: (value) => setState(() => _isRecurring = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Assign To', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _AssignOptionCard(
              icon: Icons.groups_outlined,
              title: 'Household Task',
              subtitle: 'Left open - any child can claim it',
              selected: _assignTarget == _AssignTarget.household,
              onTap: () => setState(() => _assignTarget = _AssignTarget.household),
            ),
            const SizedBox(height: 8),
            for (final child in children) ...[
              _AssignOptionCard(
                avatarEmoji: child.avatarEmoji,
                title: child.name,
                subtitle: 'Age ${child.age ?? '-'}',
                selected: _assignTarget == _AssignTarget.child && _selectedChildId == child.id,
                onTap: () => setState(() {
                  _assignTarget = _AssignTarget.child;
                  _selectedChildId = child.id;
                }),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: _isEditing ? 'Save Changes' : 'Create Task',
              icon: _isEditing ? Icons.save_outlined : Icons.add_task,
              onPressed: _canSubmit ? () => _submit(context.read<DatabaseService>()) : null,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selectedKey, required this.onSelected});

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final entry in TaskIconCatalog.all)
          _IconOption(
            entry: entry,
            selected: entry.key == selectedKey,
            onTap: () => onSelected(entry.key),
          ),
      ],
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({required this.entry, required this.selected, required this.onTap});

  final TaskIconEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: entry.label,
      child: Material(
        color: selected ? AppColors.primaryBlue : Colors.grey.shade100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.primaryBlue : Colors.grey.shade300),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Icon(entry.icon, color: selected ? Colors.white : Colors.grey.shade700),
        ),
      ),
    );
  }
}

class _AssignOptionCard extends StatelessWidget {
  const _AssignOptionCard({
    this.icon,
    this.avatarEmoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final String? avatarEmoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      color: selected ? AppColors.primaryBlue.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: avatarEmoji != null
                ? Text(avatarEmoji!, style: const TextStyle(fontSize: AppConstants.emojiIconXs))
                : Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? AppColors.primaryBlue : Colors.grey,
          ),
        ],
      ),
    );
  }
}
