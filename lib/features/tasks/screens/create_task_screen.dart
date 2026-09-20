import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/services/database_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

enum _AssignTarget { household, child }

/// "Create Task" — a parent picks an icon, names the task, sets an
/// optional due date and repeat, then either assigns it to one specific
/// child or leaves it open as a household task anyone can claim (see
/// [DatabaseService.claimTask]).
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key, this.initialChildId});

  /// Pre-selects a specific child (e.g. when reached by tapping a child
  /// from the Home or Family screen) instead of defaulting to "household".
  final String? initialChildId;

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _titleController = TextEditingController();
  String _selectedIconKey = TaskIconCatalog.defaultKey;
  DateTime? _dueDate;
  bool _isRecurring = false;
  // Set from `widget.initialChildId` in initState rather than as a field
  // initializer: field initializers run before the State is attached to
  // its widget, so `widget` isn't accessible there yet.
  late _AssignTarget _assignTarget;
  String? _selectedChildId;

  @override
  void initState() {
    super.initState();
    _selectedChildId = widget.initialChildId;
    _assignTarget = widget.initialChildId != null ? _AssignTarget.child : _AssignTarget.household;
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  void _createTask(DatabaseService db) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final assignedToUserId = _assignTarget == _AssignTarget.household ? null : _selectedChildId;

    db.addTask(
      TaskModel(
        id: 'task-${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        icon: _selectedIconKey,
        assignedToUserId: assignedToUserId,
        dueDate: _dueDate,
        isRecurring: _isRecurring,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$title" created!')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DatabaseService>();
    final children = db.children;
    final selectedChild = _selectedChildId == null ? null : db.userById(_selectedChildId!);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Task')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
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
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. Take Out the Trash'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
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
                      _dueDate == null ? 'No due date — tap to set one' : _formatDate(_dueDate!),
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
              subtitle: 'Left open — any child can claim it',
              selected: _assignTarget == _AssignTarget.household,
              onTap: () => setState(() => _assignTarget = _AssignTarget.household),
            ),
            const SizedBox(height: 8),
            for (final child in children) ...[
              _AssignOptionCard(
                avatarEmoji: child.avatarEmoji,
                title: child.name,
                subtitle: 'Age ${child.age ?? '—'}',
                selected: _assignTarget == _AssignTarget.child && _selectedChildId == child.id,
                onTap: () => setState(() {
                  _assignTarget = _AssignTarget.child;
                  _selectedChildId = child.id;
                }),
              ),
              const SizedBox(height: 8),
            ],
            if (_assignTarget == _AssignTarget.child && selectedChild != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.rewardChoose, arguments: selectedChild.id),
                icon: const Icon(Icons.card_giftcard),
                label: Text("Manage rewards for ${selectedChild.name}"),
              ),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: 'Create Task',
              icon: Icons.add_task,
              onPressed: _canSubmit ? () => _createTask(context.read<DatabaseService>()) : null,
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
