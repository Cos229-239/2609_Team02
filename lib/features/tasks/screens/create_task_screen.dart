import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/task_icons.dart';
import '../../../core/models/task.dart';
import '../../../core/models/task_schedule.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/description_suggester.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/number_stepper.dart';

enum _AssignTarget { household, child }

/// "Create Task" / "Edit Task" / "Edit Repeating Task" screen.
///
/// Passing [taskId] edits that task (for an occurrence of a repeating task:
/// just that one day). Passing [scheduleId] edits the repeating task itself.
/// Creating with a repeat other than "Does not repeat" saves a
/// [TaskSchedule]; the server then creates one task per occurrence.
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key, this.initialChildId, this.taskId, this.scheduleId});

  /// Pre-selects a child instead of defaulting to "household". Ignored
  /// when editing.
  final String? initialChildId;

  /// When set, edits this task instead of creating a new one.
  final String? taskId;

  /// When set, edits this repeating task.
  final String? scheduleId;

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _selectedIconKey;
  /// Due date (one-time) or start date (repeating).
  DateTime? _dueDate;

  /// Null = "Does not repeat".
  TaskRepeat? _repeat;
  Set<int> _weekdays = {};
  late int _xp;
  late int _coins;

  bool _requiresPhoto = false;
  // Set in initState: widget isn't accessible from field initializers.
  late _AssignTarget _assignTarget;
  String? _selectedChildId;

  /// The task being edited, or null when creating a new one.
  TaskModel? _originalTask;

  /// The repeating task being edited.
  TaskSchedule? _originalSchedule;

  bool get _isEditingSchedule => _originalSchedule != null;
  bool get _isEditing => _originalTask != null || _isEditingSchedule;

  /// Editing one occurrence of a repeating task: its cadence lives on the schedule.
  bool get _isOccurrence => _originalTask?.isRecurring ?? false;

  bool get _canChooseRepeat => !_isOccurrence;

  @override
  void initState() {
    super.initState();

    final db = context.read<DatabaseService>();
    TaskModel? existing;
    if (widget.taskId != null) {
      for (final t in db.tasks) {
        if (t.id == widget.taskId) {
          existing = t;
          break;
        }
      }
    }
    _originalTask = existing;
    final schedule = widget.scheduleId == null ? null : db.scheduleById(widget.scheduleId);
    _originalSchedule = schedule;

    _titleController = TextEditingController(text: schedule?.title ?? existing?.title ?? '');
    _descriptionController = TextEditingController(text: schedule?.description ?? existing?.description ?? '');
    _selectedIconKey = schedule?.icon ?? existing?.icon ?? TaskIconCatalog.defaultKey;
    _dueDate = schedule?.startDate ?? existing?.dueDate;
    _repeat = schedule?.repeat ?? existing?.repeat;
    _weekdays = {...?schedule?.effectiveWeekdays};
    _xp = schedule?.rewardXp ?? existing?.rewardXp ?? AppConstants.defaultTaskXp;
    _coins = schedule?.coinReward ?? existing?.coinReward ?? AppConstants.defaultTaskCoins;
    _requiresPhoto = schedule?.requiresPhoto ?? existing?.requiresPhoto ?? false;
    _selectedChildId = schedule != null
        ? schedule.assignedToUserId
        : (existing?.assignedToUserId ?? widget.initialChildId);
    _assignTarget = _selectedChildId != null ? _AssignTarget.child : _AssignTarget.household;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _titleController.text.trim().isNotEmpty;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDueDate() async {
    final today = _today;
    final initial = _dueDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // An existing task/schedule may already be dated in the past.
      firstDate: initial.isBefore(today) ? initial : today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      // Weekly cadences follow the start day until the parent picks days.
      if (_repeat != null && _repeat!.usesWeekdays && _dueDate != null &&
          _weekdays.length == 1 && _weekdays.single == _dueDate!.weekday) {
        _weekdays = {picked.weekday};
      }
      _dueDate = picked;
    });
  }

  void _setRepeat(TaskRepeat? repeat) {
    setState(() {
      _repeat = repeat;
      if (repeat != null) {
        _dueDate ??= _today; // repeating tasks need a start date
        if (repeat.usesWeekdays && _weekdays.isEmpty) _weekdays = {_dueDate!.weekday};
      }
    });
  }

  void _toggleWeekday(int day) {
    setState(() {
      if (_weekdays.contains(day)) {
        if (_weekdays.length > 1) _weekdays = {..._weekdays}..remove(day);
      } else {
        _weekdays = {..._weekdays, day};
      }
    });
  }

  TaskSchedule _buildSchedule({required String id, required String title, required String description, String? assignedToUserId}) {
    return TaskSchedule(
      id: id,
      title: title,
      description: description,
      icon: _selectedIconKey,
      rewardXp: _xp,
      coinReward: _coins,
      assignedToUserId: assignedToUserId,
      repeat: _repeat!,
      weekdays: _repeat!.usesWeekdays ? (_weekdays.toList()..sort()) : const [],
      startDate: _dueDate ?? _today,
      createdAt: _originalSchedule?.createdAt ?? DateTime.now(),
      requiresPhoto: _requiresPhoto,
    );
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
    final originalSchedule = _originalSchedule;
    void done(String message) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    }

    if (originalSchedule != null) {
      db.updateSchedule(
        originalSchedule.id,
        _buildSchedule(
          id: originalSchedule.id,
          title: title,
          description: description,
          assignedToUserId: assignedToUserId,
        ),
      );
      done('"$title" updated - upcoming days will use the changes.');
      return;
    }

    if (original != null && !original.isRecurring && _repeat != null) {
      // A one-time task turned into a repeating one: the schedule replaces it.
      db.addSchedule(_buildSchedule(id: '', title: title, description: description, assignedToUserId: assignedToUserId));
      db.removeTask(original.id);
      done('"$title" now repeats: $_repeatSummary.');
      return;
    }

    if (original == null && _repeat != null) {
      db.addSchedule(_buildSchedule(id: '', title: title, description: description, assignedToUserId: assignedToUserId));
      done('"$title" created - repeats: $_repeatSummary.');
      return;
    }

    if (original != null) {
      final updated = original.copyWith(
        title: title,
        description: description,
        icon: _selectedIconKey,
        assignedToUserId: assignedToUserId,
        clearAssignedToUserId: assignedToUserId == null,
        rewardXp: _xp,
        coinReward: _coins,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        requiresPhoto: _requiresPhoto,
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
          rewardXp: _xp,
          coinReward: _coins,
          createdAt: DateTime.now(),
          requiresPhoto: _requiresPhoto,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$title" created!')),
      );
    }

    Navigator.of(context).pop();
  }

  /// "Every Mon & Thu" etc. for the current picker state.
  String get _repeatSummary {
    if (_repeat == null) return 'Does not repeat';
    return _buildSchedule(id: '', title: '', description: '').describe();
  }

  Future<void> _confirmStopRepeating() async {
    final schedule = _originalSchedule;
    if (schedule == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop Repeating?'),
        content: Text(
          '"${schedule.title}" won\'t come back any more. Days that were already '
          'handed out stay until they\'re done; upcoming ones are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop Repeating', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<DatabaseService>().deleteSchedule(schedule.id);
    if (mounted) Navigator.of(context).pop();
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
        title: Text(_isEditingSchedule ? 'Edit Repeating Task' : (_isEditing ? 'Edit Task' : 'Create Task')),
        actions: [
          if (_isEditingSchedule)
            IconButton(
              tooltip: 'Stop repeating',
              icon: const Icon(Icons.event_busy_outlined),
              onPressed: _confirmStopRepeating,
            ),
          if (_originalTask != null)
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
            if (_isEditingSchedule) ...[
              const _InfoBanner(
                icon: Icons.repeat,
                text: 'Changes apply from tomorrow on. Today\'s task (if any) keeps its current details.',
              ),
              const SizedBox(height: 16),
            ],
            if (_isOccurrence) ...[
              _OccurrenceBanner(task: _originalTask!),
              const SizedBox(height: 16),
            ],
            if (_originalTask != null && _originalTask!.isArchived) ...[
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
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: SwitchListTile.adaptive(
                key: const ValueKey('requires-photo-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                secondary: const Icon(Icons.photo_camera_outlined),
                title: const Text('Require Photo Proof'),
                subtitle: Text(
                  'Your child takes a photo when done. It is checked on their device for a match '
                  'with this task, and you review it before approving. Photos are deleted after '
                  '${AppConstants.taskPhotoRetentionDays} days.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                value: _requiresPhoto,
                onChanged: (value) => setState(() => _requiresPhoto = value),
              ),
            ),
            const SizedBox(height: 20),
            if (_canChooseRepeat) ...[
              Text('Repeat:', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 8),
              _RepeatPicker(
                repeat: _repeat,
                weekdays: _weekdays,
                allowNone: !_isEditingSchedule,
                summary: _repeat == null
                    ? 'One-time task'
                    : '$_repeatSummary, starting ${_formatDate(_dueDate ?? _today)}',
                onRepeatChanged: _setRepeat,
                onWeekdayToggled: _toggleWeekday,
              ),
              const SizedBox(height: 20),
            ],
            Text(_repeat != null && _canChooseRepeat ? 'Starts On:' : 'Select a Due Date:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  if (_dueDate != null && (_repeat == null || !_canChooseRepeat))
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
            Text('Assign To:', style: Theme.of(context).textTheme.titleMedium),
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
              label: _isEditing ? 'Save Changes' : (_repeat != null ? 'Create Repeating Task' : 'Create Task'),
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AppCard(
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ?action,
        ],
      ),
    );
  }
}

/// Shown when editing one day of a repeating task.
class _OccurrenceBanner extends StatelessWidget {
  const _OccurrenceBanner({required this.task});

  final TaskModel task;

  @override
  Widget build(BuildContext context) {
    final schedule = context.watch<DatabaseService>().scheduleById(task.scheduleId);
    final cadence = schedule?.describe() ?? task.repeat?.label ?? 'Repeats';
    return _InfoBanner(
      icon: Icons.repeat,
      text: schedule == null
          ? 'One day of a repeating task that has since been stopped. Changes here only affect this day.'
          : '$cadence. Changes here only affect this day.',
      action: schedule == null
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(
                AppRoutes.scheduleEdit,
                arguments: schedule.id,
              ),
              child: const Text('Edit all'),
            ),
    );
  }
}

/// "Does not repeat / Every day / … / Monthly" plus weekday chips.
class _RepeatPicker extends StatelessWidget {
  const _RepeatPicker({
    required this.repeat,
    required this.weekdays,
    required this.allowNone,
    required this.summary,
    required this.onRepeatChanged,
    required this.onWeekdayToggled,
  });

  final TaskRepeat? repeat;
  final Set<int> weekdays;
  final bool allowNone;
  final String summary;
  final ValueChanged<TaskRepeat?> onRepeatChanged;
  final ValueChanged<int> onWeekdayToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TaskRepeat?>(
                    isExpanded: true,
                    value: repeat,
                    onChanged: (value) {
                      if (value != null || allowNone) onRepeatChanged(value);
                    },
                    items: [
                      if (allowNone)
                        const DropdownMenuItem<TaskRepeat?>(value: null, child: Text('Does not repeat')),
                      for (final r in TaskRepeat.values)
                        DropdownMenuItem<TaskRepeat?>(value: r, child: Text(r.label)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (repeat != null && repeat!.usesWeekdays) ...[
            const SizedBox(height: 4),
            Text('On these days:', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                  FilterChip(
                    label: Text(weekdayShortNames[day]),
                    selected: weekdays.contains(day),
                    showCheckmark: false,
                    onSelected: (_) => onWeekdayToggled(day),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}
